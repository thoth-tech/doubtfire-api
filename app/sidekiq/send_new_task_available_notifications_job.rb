# frozen_string_literal: true

# Notify students when a future-dated task becomes available.
class SendNewTaskAvailableNotificationsJob
  include Sidekiq::Job

  BATCH_SIZE = 100
  CATCH_UP_DAYS = 7
  SETTLE_TIME = 1.hour
  ROLLING_WRITER_TOLERANCE = 1.minute

  sidekiq_options lock: :until_executed,
                  lock_args_method: ->(_args) { ['send-new-task-available-notifications'] },
                  on_conflict: :reject,
                  retry: 3

  def perform
    today = Time.zone.today
    failed_project_ids = []

    Unit.where(active: true).find_each(batch_size: BATCH_SIZE) do |unit|
      notify_unit(unit, today, failed_project_ids)
    end

    return if failed_project_ids.empty?

    raise "New-task availability notifications failed for projects: #{failed_project_ids.join(', ')}"
  end

  private

  def notify_unit(unit, today, failed_project_ids)
    task_definitions = candidate_task_definitions(unit, today)
    return if task_definitions.empty?

    unit.active_projects
        .where.not(target_grade: nil)
        .includes(:user)
        .find_in_batches(batch_size: BATCH_SIZE) do |projects|
      tasks_by_project = Task
                         .where(
                           project_id: projects.map(&:id),
                           task_definition_id: task_definitions.map(&:id)
                         )
                         .includes({ project: :unit }, task_definition: :grade_due_dates)
                         .group_by(&:project_id)
                         .transform_values { |tasks| tasks.index_by(&:task_definition_id) }

      projects.each do |project|
        notify_project(
          project,
          task_definitions,
          tasks_by_project.fetch(project.id, {}),
          today
        )
      rescue StandardError => e
        failed_project_ids << project.id
        Rails.logger.error(
          "Failed new-task availability notifications for Project #{project.id}: " \
          "#{e.class} - #{e.message}"
        )
      end
    end
  end

  def candidate_task_definitions(unit, today)
    # Definitions written by an older process during a rolling deployment get
    # the database-default marker. Give multi-step imports/copies time to finish
    # before the sweep can observe them; current workflows enqueue explicitly.
    tracked = unit.task_definitions
                  .where.not(new_task_notifications_from: nil)
                  .where('created_at <= ?', Time.current - SETTLE_TIME)
    window = (today - CATCH_UP_DAYS.days).beginning_of_day..today.end_of_day

    ids = tracked.where(created_at: window).ids
    ids.concat(tracked.where(start_date: window).ids)
    ids.concat(
      TaskDefinitionGradeDueDate.where(
        task_definition_id: tracked.select(:id),
        start_date: window
      ).distinct.pluck(:task_definition_id)
    )
    ids.concat(
      Task.where(
        task_definition_id: tracked.select(:id),
        target_start_date: window
      ).distinct.pluck(:task_definition_id)
    )
    ids.concat(
      Task.where(task_definition_id: tracked.select(:id))
          .where('extensions < 0')
          .distinct
          .pluck(:task_definition_id)
    )

    tracked.where(id: ids.uniq).includes(:grade_due_dates).to_a
  end

  def notify_project(project, task_definitions, tasks, today)
    task_definitions.each do |task_definition|
      next if task_definition.target_grade > project.target_grade

      available_on = Webcal.start_date_for_task_definition(
        task_definition,
        tasks[task_definition.id],
        project
      ).to_date

      tracking_from = task_definition.new_task_notifications_from.to_date
      recently_created = task_definition.created_at >=
                         task_definition.new_task_notifications_from - ROLLING_WRITER_TOLERANCE &&
                         task_definition.created_at.to_date >= today - CATCH_UP_DAYS.days
      release_in_window = available_on.between?(
        [tracking_from, today - CATCH_UP_DAYS.days].max,
        today
      )
      next unless recently_created || release_in_window
      next if available_on > today

      NewTaskAvailableNotificationJob.deliver(project, task_definition)
    end
  end
end
