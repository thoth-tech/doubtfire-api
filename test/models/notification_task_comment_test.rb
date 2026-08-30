require 'test_helper'
require 'minitest/mock'

# EN-E01: posting a task comment notifies the other party.
class NotificationTaskCommentTest < ActiveSupport::TestCase
  include TestHelpers::PushNotificationHelper

  setup do
    ActionMailer::Base.deliveries.clear
    NotificationEmailJob.clear

    @project = FactoryBot.create(:project)
    @unit = @project.unit
    @task_definition = @unit.task_definitions.first
    @task = @project.task_for_task_definition(@task_definition)
    @student = @project.student
    @tutor = @project.tutor_for(@task_definition)
  end

  # The notification email is multipart, and Mail::Body#to_s is empty for a
  # multipart body. Reading it the naive way makes every refute_includes pass
  # for the wrong reason, so decode the parts instead.
  def delivered_body
    mail = ActionMailer::Base.deliveries.last
    return '' if mail.nil?

    mail.multipart? ? mail.parts.map { |part| part.body.decoded }.join("\n") : mail.body.decoded
  end

  def test_a_tutor_comment_notifies_the_student
    assert_difference 'Notification.count', 1 do
      @task.add_text_comment(@tutor, 'Have a look at question three.')
    end
    NotificationEmailJob.drain

    notification = Notification.recent_first.first

    assert_equal @student, notification.user
    assert_equal 'feedback', notification.notification_type
    assert_equal 'task_comment_created', notification.event
    assert_valid_push_payload(
      notification,
      expected_link: "/projects/#{@project.id}/dashboard/#{@task_definition.abbreviation}"
    )
    assert_equal 1, ActionMailer::Base.deliveries.count
    assert_equal [@student.email], ActionMailer::Base.deliveries.last.to
  end

  def test_a_student_comment_notifies_the_tutor
    assert_difference 'Notification.count', 1 do
      @task.add_text_comment(@student, 'I am stuck on question three.')
    end
    NotificationEmailJob.drain

    notification = Notification.recent_first.first

    # The recipient is the other party, never the person who commented.
    assert_equal @tutor, notification.user
    assert_not_equal @student, notification.user
    assert_equal [@tutor.email], ActionMailer::Base.deliveries.last.to
  end

  def test_no_notification_when_the_feedback_preference_is_off
    @student.update!(receive_feedback_notifications: false)

    assert_no_difference 'Notification.count' do
      @task.add_text_comment(@tutor, 'You will not be told about this.')
    end

    assert_equal 0, ActionMailer::Base.deliveries.count
  end

  def test_the_comment_text_is_not_in_the_notification_or_the_email
    secret = 'Please do not put this sentence in an email.'
    @task.add_text_comment(@tutor, secret)
    NotificationEmailJob.drain

    notification = Notification.recent_first.first
    body = delivered_body

    push = parsed_push_notification(notification)

    assert_not_empty body, 'guard: the body must be readable or this test proves nothing'
    assert_not_includes notification.message, secret
    assert_not_includes body, secret
    assert_not_includes push['body'], secret
  end

  def test_the_message_names_the_commenter_and_the_task
    @task.add_text_comment(@tutor, 'Named check.')

    message = Notification.recent_first.first.message

    assert_includes message, @tutor.name
    assert_includes message, @task_definition.abbreviation
  end

  def test_the_link_points_at_the_task_on_the_student_dashboard
    @task.add_text_comment(@tutor, 'Link check.')

    assert_equal(
      "/projects/#{@project.id}/dashboard/#{@task_definition.abbreviation}",
      Notification.recent_first.first.link
    )
  end

  def test_the_event_specific_template_is_used_instead_of_the_generic_one
    @task.add_text_comment(@tutor, 'Template check.')
    NotificationEmailJob.drain

    body = delivered_body

    # Wording that only exists in task_comment_created.*.erb. If the mailer ever
    # falls back to single_notification.*.erb this fails.
    assert_includes body, 'The comment is not included in this email'
  end

  def test_a_notification_failure_does_not_stop_the_comment_being_posted
    comment = nil

    NotificationService.stub :notify, ->(**_kwargs) { raise StandardError, 'notification exploded' } do
      comment = @task.add_text_comment(@tutor, 'This must still be saved.')
    end

    assert_not_nil comment
    assert comment.persisted?
    assert_equal 'This must still be saved.', comment.comment
  end

  def test_no_notification_and_no_error_when_there_is_no_recipient
    comment = TaskComment.new(recipient: nil)

    assert_no_difference 'Notification.count' do
      assert_nothing_raised { @task.notify_comment_recipient(comment) }
    end
  end
end
