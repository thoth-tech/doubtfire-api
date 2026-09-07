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
