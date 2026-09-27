# frozen_string_literal: true

class TaskDueDateChangedNotificationJob
  include Sidekiq::Job

  BATCH_SIZE = 100
  EVENT = 'task_due_date_changed'
  TYPE = 'task'

  sidekiq_options lock: :until_executed,
                  lock_args_method: ->(args) { args.first(4) },
                  on_conflict: :reject,
                  retry: 3

  def perform(task_definition_id, _previous_due_date, new_due_date, change_id = nil, allow_large_fanout = false) # rubocop:disable Style/OptionalBooleanParameter
    task_definition = TaskDefinition.find_by(id: task_definition_id)
    return if task_definition.nil?
    return unless task_definition.unit.active
    return unless current_due_date(task_definition) == new_due_date

    # A date can be used more than once. New API jobs carry an occurrence id;
    # pre-deployment jobs keep their Sidekiq jid across retries. The timestamp
    # fallback supports direct invocations without a Sidekiq job envelope.
    occurrence = change_id.presence || jid.presence ||
                 "#{new_due_date}:#{task_definition.updated_at.utc.iso8601(6)}"

    return unless NotificationDeliveryPolicy.fanout_allowed?(
      event: EVENT, trigger: "task-definition:#{task_definition.id}",
      recipient_count: eligible_projects(task_definition).count, allow_large_fanout: allow_large_fanout
    )

    failed_project_ids = []

    eligible_projects(task_definition).find_each(batch_size: BATCH_SIZE) do |project|
      notify_project(project, task_definition, occurrence)
    rescue StandardError => e
      failed_project_ids << project.id

      Rails.logger.error(
        "Failed due-date notification for TaskDefinition " \
        "#{task_definition.id}, Project #{project.id}: " \
        "#{e.class} - #{e.message}"
      )
    end

    return if failed_project_ids.empty?

    # Collected and re-raised so Sidekiq retries, matching
    # NewTaskAvailableNotificationJob and SendDueSoonRemindersJob. This event
    # fires once off a convenor's edit and is never swept for again, so a
    # per-project rescue that only logged left one transient insert failure
    # losing that student's notification for good. Re-running the whole sweep is
    # safe because notify_project carries a dedupe_key: a student already
    # notified for this occurrence is found, not emailed a second time.
    raise "Due-date-changed notifications failed for projects: #{failed_project_ids.join(', ')}"
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

  def notify_project(project, task_definition, occurrence)
    NotificationService.notify(
      user: project.student,
      type: TYPE,
      event: EVENT,
      message: "The due date for #{task_definition.abbreviation} " \
               "in #{task_definition.unit.code} has changed.",
      link: "/projects/#{project.id}/dashboard/" \
            "#{ERB::Util.url_encode(task_definition.abbreviation)}",
      # Retries share an occurrence; a later edit back to the same date does
      # not. The unique index scopes this key to each recipient.
      dedupe_key: "#{EVENT}:task-definition:#{task_definition.id}:#{occurrence}"
    )
  end
end
