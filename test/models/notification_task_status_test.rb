require 'test_helper'
require 'minitest/mock'

# EN-E02: a staff status change notifies the student. A student's own action
# does not.
class NotificationTaskStatusTest < ActiveSupport::TestCase
  include TestHelpers::PushNotificationHelper

  setup do
    ActionMailer::Base.deliveries.clear
    NotificationEmailJob.clear

    @project = FactoryBot.create(:project)
    @unit = @project.unit
    @task_definition = @unit.task_definitions.first
    @task = @project.task_for_task_definition(@task_definition)
    @student = @project.student
    @tutor = @unit.main_convenor_user

    # Put the task where a tutor can mark it, then start from a clean inbox so
    # the setup's own status comment does not count towards the assertions.
    @task.update!(task_status: TaskStatus.ready_for_feedback)
    @task.add_status_comment(@student, TaskStatus.ready_for_feedback)
    ActionMailer::Base.deliveries.clear
    NotificationEmailJob.clear
  end

  # The notification email is multipart, and Mail::Body#to_s is empty for a
  # multipart body. Reading it the naive way makes every refute pass for the
  # wrong reason, so decode the parts instead.
  def delivered_body
    mail = ActionMailer::Base.deliveries.last
    return '' if mail.nil?

    mail.multipart? ? mail.parts.map { |part| part.body.decoded }.join("\n") : mail.body.decoded
  end

  def test_a_staff_status_change_notifies_the_student
    assert_difference 'Notification.count', 1 do
      assert @task.trigger_transition(trigger: 'discuss', by_user: @tutor)
    end
    NotificationEmailJob.drain

    notification = Notification.recent_first.first

    assert_equal @student, notification.user
    assert_equal 'task', notification.notification_type
    assert_equal 'task_status_changed', notification.event
    assert_valid_push_payload(
      notification,
      expected_link: "/projects/#{@project.id}/dashboard/#{@task_definition.abbreviation}"
    )
    assert_equal 1, ActionMailer::Base.deliveries.count
    assert_equal [@student.email], ActionMailer::Base.deliveries.last.to
  end

  def test_a_students_own_action_notifies_nobody
    assert_no_difference 'Notification.count' do
      assert @task.trigger_transition(trigger: 'working_on_it', by_user: @student)
    end

    assert_equal 0, ActionMailer::Base.deliveries.count
  end

  def test_an_unchanged_status_notifies_nobody
    @task.trigger_transition(trigger: 'discuss', by_user: @tutor)
    ActionMailer::Base.deliveries.clear
    NotificationEmailJob.clear

    # Re-applying the same status is a no-op: no change, no notification.
    assert_no_difference 'Notification.count' do
      @task.trigger_transition(trigger: 'discuss', by_user: @tutor)
    end

    assert_equal 0, ActionMailer::Base.deliveries.count
  end

  def test_no_notification_when_the_task_preference_is_off
    @student.update!(receive_task_notifications: false)

    assert_no_difference 'Notification.count' do
      @task.trigger_transition(trigger: 'discuss', by_user: @tutor)
    end

    assert_equal 0, ActionMailer::Base.deliveries.count
  end

  def test_the_status_value_is_not_in_the_notification_or_the_email
    @task.trigger_transition(trigger: 'discuss', by_user: @tutor)
    NotificationEmailJob.drain

    notification = Notification.recent_first.first
    body = delivered_body

    push = parsed_push_notification(notification)

    assert_not_empty body, 'guard: the body must be readable or this test proves nothing'
    assert_not_includes notification.message, 'Discuss'
    assert_not_includes body, 'Discuss'
    assert_not_includes push['body'], 'Discuss'
  end

  def test_the_message_names_the_actor_and_the_task
    @task.trigger_transition(trigger: 'discuss', by_user: @tutor)

    message = Notification.recent_first.first.message

    assert_includes message, @tutor.name
    assert_includes message, @task_definition.abbreviation
  end

  def test_the_link_points_at_the_task_on_the_student_dashboard
    @task.trigger_transition(trigger: 'discuss', by_user: @tutor)

    assert_equal(
      "/projects/#{@project.id}/dashboard/#{@task_definition.abbreviation}",
      Notification.recent_first.first.link
    )
  end

  def test_the_event_specific_template_is_used_instead_of_the_generic_one
    @task.trigger_transition(trigger: 'discuss', by_user: @tutor)
    NotificationEmailJob.drain

    body = delivered_body

    # Wording that only exists in task_status_changed.*.erb. If the mailer ever
    # falls back to single_notification.*.erb this fails.
    assert_includes body, 'The new status is not included in this email'
  end

  def test_bulk_marking_still_notifies_one_per_task
    # This event ignores the bulk: flag on purpose (see the event doc): a bulk
    # mark still notifies. One call, one task, one email.
    assert_difference 'Notification.count', 1 do
      assert @task.trigger_transition(trigger: 'discuss', by_user: @tutor, bulk: true)
    end
    NotificationEmailJob.drain

    assert_equal 1, ActionMailer::Base.deliveries.count
    assert_equal [@student.email], ActionMailer::Base.deliveries.last.to
  end

  def test_a_notification_failure_does_not_stop_the_transition
    result = nil

    NotificationService.stub :notify, ->(**_kwargs) { raise StandardError, 'notification exploded' } do
      result = @task.trigger_transition(trigger: 'discuss', by_user: @tutor)
    end

    assert result, 'the transition must still succeed'
    assert_equal TaskStatus.discuss, @task.reload.task_status
  end
end
