# frozen_string_literal: true

class NewTaskAvailableNotificationJob
  include Sidekiq::Job

  BATCH_SIZE = 100
  EVENT = 'new_task_available'
  TYPE = 'task'

  sidekiq_options lock: :until_executed,
                  lock_args_method: ->(args) { [args.first] },
                  on_conflict: :reject,
                  retry: 3

  def self.enqueue(task_definition_id)
    perform_async(task_definition_id)
  rescue StandardError => e
    Rails.logger.error(
      "Failed to enqueue new-task notification for TaskDefinition #{task_definition_id}: " \
      "#{e.class} - #{e.message}"
    )
    nil
  end

  def self.track_and_enqueue(task_definition)
    task_definition.enable_new_task_notifications!
    enqueue(task_definition.id)
  rescue StandardError => e
    Rails.logger.error(
      "Failed to track new-task notification for TaskDefinition #{task_definition.id}: " \
      "#{e.class} - #{e.message}"
    )
    enqueue(task_definition.id)
  end

  def self.track_and_enqueue_all(task_definitions)
    task_definition_ids = task_definitions.map do |task_definition|
      begin
        task_definition.enable_new_task_notifications!
      rescue StandardError => e
        Rails.logger.error(
          "Failed to track new-task notification for TaskDefinition #{task_definition.id}: " \
          "#{e.class} - #{e.message}"
        )
      end

      task_definition.id
    end

    perform_bulk(task_definition_ids.map { |id| [id] }) unless task_definition_ids.empty?
  rescue StandardError => e
    Rails.logger.error(
      "Failed to bulk enqueue new-task notifications: #{e.class} - #{e.message}"
    )
    nil
  end

  def self.deliver(project, task_definition)
    notification = nil

    # Recheck mutable eligibility under a short row lock. The reservation is
    # committed before channel jobs are handed off; provider network I/O occurs
    # in workers and never holds the project lock.
    project.with_lock do
      project.reload
      unit = project.unit
      eligible = unit.active && project.enrolled && project.target_grade.present? &&
                 task_definition.target_grade <= project.target_grade

      if eligible
        notification = NotificationService.reserve(
          user: project.student,
          type: TYPE,
          event: EVENT,
          message: "A new task is available: #{task_definition.abbreviation} in #{unit.code}.",
          link: "/projects/#{project.id}/dashboard/#{task_definition.abbreviation}",
          dedupe_key: "#{EVENT}:task-definition:#{task_definition.id}"
        )
      end
    end

    NotificationService.deliver(notification)
  end

  def perform(task_definition_id)
    task_definition = TaskDefinition.find_by(id: task_definition_id)
    return if task_definition.nil?

    # If the workflow's best-effort marker write failed, the queued job repairs
    # it before checking availability. A transient database failure raises and
    # lets Sidekiq retry instead of losing a future release permanently.
    task_definition.enable_new_task_notifications! if task_definition.new_task_notifications_from.nil?

    unit = task_definition.unit
    return unless unit.active

    failed_project_ids = []

    unit.projects.where(enrolled: true).includes(:user).find_in_batches(batch_size: BATCH_SIZE) do |projects|
      tasks = Task.where(
        project_id: projects.map(&:id),
        task_definition_id: task_definition.id
      ).includes({ project: :unit }, task_definition: :grade_due_dates).index_by(&:project_id)

      projects.each do |project|
        notify_project(project, task_definition, tasks[project.id])
      rescue StandardError => e
        failed_project_ids << project.id

        Rails.logger.error(
          "Failed new-task notification for TaskDefinition #{task_definition.id}, " \
          "Project #{project.id}: #{e.class} - #{e.message}"
        )
      end
    end

    return if failed_project_ids.empty?

    raise "New-task notifications failed for projects: #{failed_project_ids.join(', ')}"
  end

  private

  def notify_project(project, task_definition, task)
    return if project.target_grade.nil?
    return if task_definition.target_grade > project.target_grade

    # A newly created task is only available when the student's effective
    # start date has arrived. Webcal applies flexible, grade-specific and
    # student-specific dates without creating a Task row just to notify.
    available_on = Webcal.start_date_for_task_definition(
      task_definition,
      task,
      project
    )
    return if available_on.to_date > Time.zone.today

    self.class.deliver(project, task_definition)
  end
end
