# frozen_string_literal: true

# Remind students about work that is nearly due.
#
# Every other notification in this feature hangs off something a person did: a
# comment was posted, a due date was edited, a status changed. A deadline
# approaching is nobody doing anything, so there is no model to hook and this
# has to be swept for on a schedule. config/schedule.yml runs it.
#
# Recipients come from projects and not from Task rows. OnTrack creates a Task
# row the first time anyone touches the task, so the students who have not
# started have no row, and they are exactly the ones a reminder is for.
#
# Nothing here may call Project#task_for_task_definition, which creates the row
# it cannot find, and nothing may call Project#task_definitions_and_status
# either, because that calls it. This reads project.tasks once per project and
# looks the row up in a hash instead.
class SendDueSoonRemindersJob
  include Sidekiq::Job

  BATCH_SIZE = 100
  EVENT = 'task_due_soon'
  TYPE = 'task'

  # How far ahead counts as soon, in days.
  #
  # Three, which is long enough to still do something about it over a weekend
  # and short enough that the reminder is about this task rather than about the
  # rest of the trimester. Project#top_tasks uses seven for the same idea, and
  # seven days of warning on a weekly task is most of the tasks a student has,
  # which is a list rather than a reminder.
  WINDOW_DAYS = 3

  # The statuses that mean the student still owes work.
  #
  # :discuss and :demonstrate are deliberately out. Both mean the student has
  # submitted and is waiting on a tutor, so telling them their task is due soon
  # is both wrong and the kind of wrong that makes people stop reading
  # notifications. Everything past those, complete and fail and the rest, is
  # finished with as far as a deadline is concerned.
  OUTSTANDING_STATUSES = %i[
    not_started
    working_on_it
    need_help
    fix_and_resubmit
    redo
  ].freeze

  sidekiq_options lock: :until_executed,
                  lock_args_method: ->(_args) { ['send-due-soon-reminders'] },
                  on_conflict: :reject,
                  retry: 1

  def perform
    today = Time.zone.today
    horizon = today + WINDOW_DAYS.days
    failed_project_ids = []

    # Units first and then their projects, the same shape as
    # NewTaskAvailableNotificationJob, so the unit and its task definitions are
    # loaded once per cohort rather than once per student.
    Unit.where(active: true).find_each(batch_size: BATCH_SIZE) do |unit|
      remind_unit(unit, today, horizon, failed_project_ids)
    end

    return if failed_project_ids.empty?

    # Collected and re-raised at the end rather than swallowed, which is what
    # NewTaskAvailableNotificationJob does and for the same reason. Logging and
    # carrying on would leave perform successful, Sidekiq would schedule no
    # retry, and a student whose task is due today is filtered out as overdue
    # tomorrow, so that reminder is gone for good. Re-running the whole sweep is
    # safe because of the duplicate guard in notify.
    raise "Due-soon reminders failed for projects: #{failed_project_ids.join(', ')}"
  end

  private

  def remind_unit(unit, today, horizon, failed_project_ids)
    # Read once for the whole cohort. Asking per project is where the query
    # count runs away: five hundred students against twenty task definitions is
    # five hundred of the same query.
    task_definitions = unit.task_definitions.to_a
    return if task_definitions.empty?

    unit.active_projects
        .where.not(target_grade: nil)
        .includes(:user)
        .find_each(batch_size: BATCH_SIZE) do |project|
      remind_project(project, unit, task_definitions, today, horizon)
    rescue StandardError => e
      failed_project_ids << project.id

      Rails.logger.error(
        "Failed due-soon reminders for Project #{project.id}: #{e.class} - #{e.message}"
      )
    end
  end

  def remind_project(project, unit, task_definitions, today, horizon)
    # One query for this student's rows, then look each one up. The row is only
    # read, never created.
    tasks = project.tasks.includes(:task_status, :task_definition).index_by(&:task_definition_id)

    task_definitions.each do |task_definition|
      next if task_definition.target_grade > project.target_grade

      task = tasks[task_definition.id]
      next unless outstanding?(task)

      due = due_date_for(task_definition, task, project)
      next if due.nil?

      due = due.to_date
      next if due < today || due > horizon

      notify(project, unit, task_definition)
    end
  end

  # Whether this student still owes work on this task.
  #
  # No row means nobody has touched it, which is not_started by any other name
  # and is the state a reminder is most for.
  def outstanding?(task)
    return true if task.nil?

    OUTSTANDING_STATUSES.include?(task.status)
  end

  # When this task is due for this student.
  #
  # Webcal already answers exactly this question, for exactly this pair of
  # cases, and it is what the calendar feed shows the student. Writing it again
  # here would mean two answers to "when is this due" that could disagree.
  #
  # With a Task row it is Task#local_due_date, which knows about extensions and
  # about a unit's flexible dates. Without one it is still not simply the task
  # definition's target date: on a unit with flexible dates the grade level
  # override applies before any row exists, so a grade 2 student can be due days
  # away from the unit's own date without ever having opened the task.
  def due_date_for(task_definition, task, project)
    Webcal.end_date_for_task_definition(task_definition, task, project)
  end

  def notify(project, unit, task_definition)
    student = project.student
    link = "/projects/#{project.id}/dashboard/#{task_definition.abbreviation}"

    # One reminder per student per task, ever.
    #
    # This job runs again tomorrow and the task is still due soon tomorrow, so
    # without this the same student is reminded every morning until the deadline
    # passes. The index on (user_id, event) is what makes asking cheap enough to
    # do once per candidate task.
    return if Notification.exists?(
      user_id: student.id,
      notification_type: TYPE,
      event: EVENT,
      link: link
    )

    NotificationService.notify(
      user: student,
      type: TYPE,
      event: EVENT,
      message: "#{task_definition.abbreviation} in #{unit.code} is due soon.",
      link: link
    )
  end
end
