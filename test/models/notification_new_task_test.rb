# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

# EN-V02: newly available tasks notify eligible students.
class NotificationNewTaskTest < ActiveSupport::TestCase
  include TestHelpers::PushNotificationHelper

  setup do
    ActionMailer::Base.deliveries.clear
    NotificationEmailJob.clear

    @unit = FactoryBot.create(
      :unit,
      with_students: false,
      task_count: 0,
      tutorials: 0,
      outcome_count: 0,
      staff_count: 0,
      campus_count: 1,
      active: true,
      start_date: Time.zone.now - 1.week,
      end_date: Time.zone.now + 12.weeks
    )

    @campus = Campus.first

    @student = FactoryBot.create(
      :user,
      :student,
      receive_task_notifications: true
    )

    @project = FactoryBot.create(
      :project,
      unit: @unit,
      campus: @campus,
      user: @student,
      enrolled: true,
      target_grade: 2
    )

    @task_definition = FactoryBot.create(
      :task_definition,
      unit: @unit,
      outcome_count: 0,
      target_grade: 1,
      start_date: Time.zone.now - 1.day,
      target_date: Time.zone.now + 1.week,
      due_date: Time.zone.now + 2.weeks
    )
  end

  def run_job
    NewTaskAvailableNotificationJob.new.perform(@task_definition.id)
    NotificationEmailJob.drain
  end

  def event_notifications
    Notification.where(event: 'new_task_available')
  end

  def delivered_body
    mail = ActionMailer::Base.deliveries.last
    return '' if mail.nil?

    if mail.multipart?
      mail.parts.map { |part| part.body.decoded }.join("\n")
    else
      mail.body.decoded
    end
  end

  def test_available_task_notifies_eligible_student
    assert_difference 'Notification.count', 1 do
      assert_no_difference 'Task.count' do
        run_job
      end
    end

    notification = event_notifications.last

    assert_equal @student, notification.user
    assert_equal 'task', notification.notification_type
    assert_equal 'new_task_available', notification.event

    assert_equal(
      "A new task is available: #{@task_definition.abbreviation} in #{@unit.code}.",
      notification.message
    )

    assert_equal(
      "/projects/#{@project.id}/dashboard/#{@task_definition.abbreviation}",
      notification.link
    )
    assert_valid_push_payload(
      notification,
      expected_link: "/projects/#{@project.id}/dashboard/#{@task_definition.abbreviation}"
    )

    assert_equal 1, ActionMailer::Base.deliveries.count
    assert_equal [@student.email], ActionMailer::Base.deliveries.last.to

    body = delivered_body

    assert_not_empty body
    assert_includes body, 'A new task is now available'
    assert_includes body, @task_definition.abbreviation
  end

  def test_fans_out_to_each_eligible_student
    second_student = FactoryBot.create(
      :user,
      :student,
      receive_task_notifications: true
    )

    FactoryBot.create(
      :project,
      unit: @unit,
      campus: @campus,
      user: second_student,
      enrolled: true,
      target_grade: 2
    )

    assert_difference 'Notification.count', 2 do
      run_job
    end

    recipients = event_notifications.includes(:user).map(&:user)

    assert_includes recipients, @student
    assert_includes recipients, second_student
    assert_equal 2, ActionMailer::Base.deliveries.count
  end

  def test_student_with_task_notifications_disabled_is_not_notified
    @student.update!(receive_task_notifications: false)

    assert_no_difference 'Notification.count' do
      run_job
    end

    assert_empty ActionMailer::Base.deliveries
  end

  def test_unenrolled_student_is_not_notified
    @project.update!(enrolled: false)

    assert_no_difference 'Notification.count' do
      run_job
    end

    assert_empty ActionMailer::Base.deliveries
  end

  def test_student_below_task_target_grade_is_not_notified
    @project.update!(target_grade: 0)

    assert_no_difference 'Notification.count' do
      run_job
    end

    assert_empty ActionMailer::Base.deliveries
  end

  def test_inactive_unit_does_not_send_notifications
    @unit.update!(active: false)

    assert_no_difference 'Notification.count' do
      run_job
    end

    assert_empty ActionMailer::Base.deliveries
  end

  def test_future_effective_student_start_date_is_not_notified
    @unit.update!(allow_flexible_dates: true)

    task = @project.task_for_task_definition(@task_definition)

    task.update!(
      target_start_date: Time.zone.now + 2.days
    )

    assert_operator task.local_start_date.to_date, :>, Time.zone.today

    assert_no_difference 'Notification.count' do
      run_job
    end

    assert_empty ActionMailer::Base.deliveries
  end

  def test_notification_failure_makes_job_fail_for_retry
    notification_failure = lambda do |_notification|
      raise StandardError, 'temporary notification failure'
    end

    NotificationService.stub(:deliver, notification_failure) do
      error = assert_raises(RuntimeError) do
        run_job
      end

      assert_includes error.message, @project.id.to_s
    end

    notification = event_notifications.find_by!(user: @student)
    assert_nil notification.delivered_at

    assert_no_difference 'Notification.count' do
      run_job
    end

    assert_not_nil notification.reload.delivered_at
    assert_equal 1, ActionMailer::Base.deliveries.count
  end

  def test_job_has_limited_retries
    assert_equal(
      3,
      NewTaskAvailableNotificationJob.get_sidekiq_options['retry']
    )
  end

  def test_running_fan_out_twice_does_not_duplicate_notification
    run_job

    assert_equal 1, event_notifications.count
    assert_equal 1, ActionMailer::Base.deliveries.count

    assert_no_difference 'Notification.count' do
      run_job
    end

    assert_equal 1, event_notifications.count
    assert_equal 1, ActionMailer::Base.deliveries.count
  end

  def test_delivery_rechecks_a_stale_project_after_withdrawal
    stale_project = Project.find(@project.id)
    @project.update!(enrolled: false)

    assert_no_difference 'Notification.count' do
      NewTaskAvailableNotificationJob.deliver(stale_project, @task_definition)
    end

    assert_empty ActionMailer::Base.deliveries
  end

  def test_renaming_a_task_does_not_send_a_second_availability_notification
    run_job
    @task_definition.update!(abbreviation: "RENAMED#{SecureRandom.hex(3)}")

    assert_no_difference 'Notification.count' do
      run_job
    end

    assert_equal 1, ActionMailer::Base.deliveries.count
  end

  def test_reusing_an_abbreviation_for_a_new_task_still_notifies
    reused_abbreviation = @task_definition.abbreviation
    run_job
    @task_definition.update!(abbreviation: "RETIRED#{SecureRandom.hex(3)}")

    replacement = FactoryBot.create(
      :task_definition,
      unit: @unit,
      outcome_count: 0,
      abbreviation: reused_abbreviation,
      target_grade: 1,
      start_date: 1.day.ago,
      target_date: 1.week.from_now
    )

    assert_difference 'Notification.count', 1 do
      NewTaskAvailableNotificationJob.new.perform(replacement.id)
    end
    # This call bypasses run_job, so it has to drain the mail queue itself.
    NotificationEmailJob.drain

    assert_equal 2, ActionMailer::Base.deliveries.count
  end
end
