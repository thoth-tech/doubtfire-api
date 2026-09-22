# frozen_string_literal: true

require 'test_helper'

class TaskDueDateChangedNotificationJobTest < ActiveSupport::TestCase
  include TestHelpers::PushNotificationHelper

  EVENT = 'task_due_date_changed'

  setup do
    @unit = FactoryBot.create(:unit, task_count: 0)
    @task_def = FactoryBot.create(
      :task_definition,
      unit: @unit,
      target_grade: 1
    )

    @previous_due_date = @task_def[:due_date]&.to_date&.iso8601
    changed_due_date = (@task_def.due_date + 1.week).to_date

    @task_def.update!(due_date: changed_due_date)
    @new_due_date = changed_due_date.iso8601

    ActionMailer::Base.deliveries.clear
  end

  def test_notifies_every_eligible_student_without_creating_tasks
    expected = eligible_projects.count

    assert_operator expected, :>=, 2
    assert_equal 0, @task_def.tasks.count

    assert_difference 'Notification.count', expected do
      assert_no_difference 'Task.count' do
        run_job
      end
    end

    assert_equal expected, ActionMailer::Base.deliveries.count
  end

  def test_does_not_notify_student_below_target_grade
    project = @unit.active_projects.find_by!(target_grade: 0)

    run_job

    assert_not Notification.exists?(
      user: project.student,
      event: EVENT
    )
  end

  def test_does_not_notify_withdrawn_student
    project = @unit.projects.find_by!(enrolled: false)
    project.update!(target_grade: 3)

    run_job

    assert_not Notification.exists?(
      user: project.student,
      event: EVENT
    )
  end

  def test_respects_task_notification_preference
    project = eligible_projects.first
    project.student.update!(receive_task_notifications: false)

    run_job

    assert_not Notification.exists?(
      user: project.student,
      event: EVENT
    )
  end

  def test_does_not_notify_for_inactive_unit
    @unit.update!(active: false)

    assert_no_difference 'Notification.count' do
      run_job
    end
  end

  def test_skips_stale_job_after_another_due_date_change
    @task_def.update!(due_date: @task_def.due_date + 1.week)

    assert_no_difference 'Notification.count' do
      run_job
    end
  end

  def test_direct_model_change_does_not_enqueue_job
    task_definition = FactoryBot.create(
      :task_definition,
      unit: @unit,
      target_grade: 1
    )

    assert_no_difference(
      -> { TaskDueDateChangedNotificationJob.jobs.size }
    ) do
      task_definition.update!(
        due_date: task_definition.due_date + 1.day
      )
    end
  end

  def test_message_and_link_are_privacy_safe
    project = eligible_projects.first

    run_job

    notification = Notification.find_by!(
      user: project.student,
      event: EVENT
    )

    assert_includes notification.message, @task_def.abbreviation
    assert_includes notification.message, @unit.code
    assert_not_includes notification.message, @new_due_date

    assert_equal(
      "/projects/#{project.id}/dashboard/#{@task_def.abbreviation}",
      notification.link
    )
    push = assert_valid_push_payload(
      notification,
      expected_link: "/projects/#{project.id}/dashboard/#{@task_def.abbreviation}"
    )
    assert_not_includes push['body'], @new_due_date
  end

  def test_event_specific_template_is_used
    run_job

    assert_includes(
      delivered_body,
      'The new due date is not included in this email'
    )
  end

  # Regression: a task abbreviation with a space must be percent-encoded in the
  # stored link, so the email href and plain-text URL are valid. Every other
  # notification event encodes the abbreviation; this job was the one that did
  # not, so a space landed raw in the href.
  def test_link_is_url_encoded_for_a_spaced_abbreviation
    @task_def.update!(abbreviation: 'AB 1.1')
    project = eligible_projects.first

    run_job

    notification = Notification.find_by!(
      user: project.student,
      event: EVENT
    )

    assert_equal(
      "/projects/#{project.id}/dashboard/AB%201.1",
      notification.link
    )
  end

  # Regression: re-running the sweep for the same change must not notify a
  # student twice. retry: 3 plus a duplicate enqueue can run perform again, so
  # the notify carries a dedupe_key; the second run finds the existing row
  # instead of sending a second email.
  def test_re_running_the_same_change_does_not_notify_twice
    expected = eligible_projects.count
    assert_operator expected, :>=, 2

    assert_difference 'Notification.count', expected do
      run_job
    end

    assert_no_difference 'Notification.count' do
      assert_no_difference(-> { ActionMailer::Base.deliveries.count }) do
        run_job
      end
    end
  end

  # Regression: a genuine second change to a different date must notify again.
  # The dedupe_key includes the new due date, so a new date is a new key.
  def test_a_later_change_to_a_different_date_notifies_again
    expected = eligible_projects.count

    assert_difference 'Notification.count', expected do
      run_job
    end

    later = (@task_def.due_date + 2.weeks).to_date
    @task_def.update!(due_date: later)
    @new_due_date = later.iso8601

    assert_difference 'Notification.count', expected do
      run_job
    end
  end

  # Regression: a transient failure for one recipient must re-raise so Sidekiq
  # retries the sweep, not be logged and swallowed. This event fires once off a
  # convenor's edit and is never swept for again, so a swallowed failure loses
  # that student's notification for good. Matches NewTaskAvailableNotificationJob.
  def test_re_raises_so_sidekiq_retries_when_a_recipient_fails
    NotificationService.stub(:notify, ->(*_args, **_kwargs) { raise 'transient insert failure' }) do
      assert_raises(RuntimeError) do
        TaskDueDateChangedNotificationJob.new.perform(
          @task_def.id,
          @previous_due_date,
          @new_due_date
        )
      end
    end
  end

  def test_returning_to_a_previously_used_date_notifies_again
    expected = eligible_projects.count
    first_date = @new_due_date
    run_job

    @task_def.update!(due_date: @task_def.due_date + 2.weeks)
    @new_due_date = @task_def[:due_date].to_date.iso8601
    run_job

    @task_def.update!(due_date: first_date)
    @new_due_date = first_date
    assert_difference 'Notification.count', expected do
      run_job
    end
  end

  def test_explicit_occurrence_is_stable_across_retries_and_unrelated_edits
    job = TaskDueDateChangedNotificationJob.new
    change_id = SecureRandom.uuid
    job.perform(@task_def.id, @previous_due_date, @new_due_date, change_id)
    @task_def.update!(name: 'Updated task name')

    assert_no_difference 'Notification.count' do
      job.perform(@task_def.id, @previous_due_date, @new_due_date, change_id)
    end
  end

  def test_legacy_three_argument_job_uses_its_stable_sidekiq_id
    job = TaskDueDateChangedNotificationJob.new
    job.jid = 'legacy-job-id'
    job.perform(@task_def.id, @previous_due_date, @new_due_date)
    @task_def.update!(name: 'Updated task name')

    assert_no_difference 'Notification.count' do
      job.perform(@task_def.id, @previous_due_date, @new_due_date)
    end
  end

  private

  def run_job
    TaskDueDateChangedNotificationJob.new.perform(
      @task_def.id,
      @previous_due_date,
      @new_due_date
    )
    NotificationEmailJob.drain
  end

  def eligible_projects
    @unit.active_projects.where(
      'projects.target_grade >= ?',
      @task_def.target_grade
    )
  end

  def delivered_body
    mail = ActionMailer::Base.deliveries.last
    return '' if mail.nil?
    return mail.body.decoded unless mail.multipart?

    mail.parts.map { |part| part.body.decoded }.join("\n")
  end
end
