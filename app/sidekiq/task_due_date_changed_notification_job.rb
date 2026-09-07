# frozen_string_literal: true

class TaskDueDateChangedNotificationJob
  include Sidekiq::Job

  BATCH_SIZE = 100
  EVENT = 'task_due_date_changed'
  TYPE = 'task'

  sidekiq_options lock: :until_executed,
                  lock_args_method: ->(args) { args.first(3) },
                  on_conflict: :reject,
                  retry: false

  def perform(task_definition_id, _previous_due_date, new_due_date)
    task_definition = TaskDefinition.find_by(id: task_definition_id)
    return if task_definition.nil?
    return unless task_definition.unit.active
    return unless current_due_date(task_definition) == new_due_date

    eligible_projects(task_definition).find_each(batch_size: BATCH_SIZE) do |project|
      notify_project(project, task_definition)
    end
  end

  private

  def eligible_projects(task_definition)
    task_definition.unit
                   .active_projects
                   .where(
                     'projects.target_grade >= ?',
                     task_definition.target_grade
                   )
                   .includes(:user)
  end

  def current_due_date(task_definition)
    task_definition[:due_date]&.to_date&.iso8601
  end

  def notify_project(project, task_definition)
    NotificationService.notify(
      user: project.student,
      type: TYPE,
      event: EVENT,
      message: "The due date for #{task_definition.abbreviation} " \
               "in #{task_definition.unit.code} has changed.",
      link: "/projects/#{project.id}/dashboard/" \
            "#{task_definition.abbreviation}"
    )
  rescue StandardError => e
    Rails.logger.error(
      "Failed due-date notification for TaskDefinition " \
      "#{task_definition.id}, Project #{project.id}: " \
      "#{e.class} - #{e.message}"
    )
  end
end
