require 'test_helper'
require 'minitest/mock'

# EN-E03: assessing an extension request notifies the student.
class NotificationExtensionTest < ActiveSupport::TestCase
  include TestHelpers::PushNotificationHelper

  EXTENSION_REQUEST_TEXT =
    'Private extension request text that must stay inside OnTrack.'.freeze

  setup do
    ActionMailer::Base.deliveries.clear
    NotificationEmailJob.clear

    @project = FactoryBot.create(:project)
    @unit = @project.unit
    @task_definition = @unit.task_definitions.first
    @task_definition.update!(due_date: @task_definition.target_date + 2.weeks)
    @task = @project.task_for_task_definition(@task_definition)

    @student = @project.student
    @tutor = @project.tutor_for(@task_definition)

    # Prevent the request being assessed automatically when it is created.
    @unit.update!(auto_apply_extension_before_deadline: false)
  end

  def create_extension_request
    @task.apply_for_extension(
      @student,
      EXTENSION_REQUEST_TEXT,
      1
    )
  end

  def delivered_parts
    mail = ActionMailer::Base.deliveries.last

    {
      html: mail&.html_part&.body&.decoded.to_s,
      text: mail&.text_part&.body&.decoded.to_s
    }
  end

  def test_granted_extension_notifies_student_with_new_date
    extension = create_extension_request

    assert_difference 'Notification.count', 1 do
      extension.assess_extension(@tutor, true)
    end
    NotificationEmailJob.drain

    extension.reload
    notification = Notification.recent_first.first

    assert_equal @student, notification.user
    assert_equal 'extension', notification.notification_type
    assert_equal 'extension_assessed', notification.event
    push = assert_valid_push_payload(
      notification,
      expected_link: "/projects/#{@project.id}/dashboard/#{@task_definition.abbreviation}"
    )
    assert_not_includes notification.message, EXTENSION_REQUEST_TEXT
    assert_not_includes push['body'], EXTENSION_REQUEST_TEXT

    assert extension.extension_granted
    assert_includes notification.message, 'Extension granted'
    assert_includes(
      notification.message,
      @task.reload.due_date.strftime('%a %b %e')
    )

    assert_equal 1, ActionMailer::Base.deliveries.count
    assert_equal [@student.email], ActionMailer::Base.deliveries.last.to

    parts = delivered_parts

    assert_not_empty parts[:html]
    assert_not_empty parts[:text]

    assert_includes parts[:html], notification.message
    assert_includes parts[:text], notification.message

    assert_includes parts[:html], notification.link
    assert_includes parts[:text], notification.link
  end

  def test_denied_extension_notifies_student
    extension = create_extension_request

    assert_difference 'Notification.count', 1 do
      extension.assess_extension(@tutor, false)
    end
    NotificationEmailJob.drain

    extension.reload
    notification = Notification.recent_first.first

    assert_not extension.extension_granted

    assert_equal @student, notification.user
    assert_equal 'extension', notification.notification_type
    assert_equal 'extension_assessed', notification.event
    assert_equal 'Extension rejected', notification.message

    assert_equal 1, ActionMailer::Base.deliveries.count

    parts = delivered_parts

    assert_includes parts[:html], 'Extension rejected'
    assert_includes parts[:text], 'Extension rejected'
  end

  def test_already_assessed_extension_does_not_send_another_notification
    extension = create_extension_request

    extension.assess_extension(@tutor, false)

    ActionMailer::Base.deliveries.clear
    NotificationEmailJob.clear

    assert_no_difference 'Notification.count' do
      result = extension.assess_extension(@tutor, true)

      assert_equal false, result
    end

    assert_empty ActionMailer::Base.deliveries
  end

  def test_deadline_error_does_not_send_notification
    extension = create_extension_request

    ActionMailer::Base.deliveries.clear

    @task.stub :can_apply_for_extension?, false do
      assert_no_difference 'Notification.count' do
        extension.assess_extension(@tutor, true)
      end
    end

    assert_empty ActionMailer::Base.deliveries
  end

  def test_failed_grant_does_not_assess_or_notify_student
    extension = create_extension_request
    task = extension.task
    original_extensions = task.extensions

    task.stub :can_apply_for_extension?, true do
      task.stub :grant_extension, false do
        assert_no_difference 'Notification.count' do
          result = extension.assess_extension(@tutor, true)

          assert_equal false, result
        end
      end
    end

    assert_empty ActionMailer::Base.deliveries
    assert_includes extension.errors[:extension], 'could not be applied'
    assert_not extension.assessed?
    assert_not extension.extension_granted
    assert_equal original_extensions, task.reload.extensions

    extension.reload
    assert_not extension.assessed?
    assert_not extension.extension_granted
  end

  def test_extension_notification_uses_event_specific_templates
    extension = create_extension_request

    extension.assess_extension(@tutor, false)
    NotificationEmailJob.drain

    parts = delivered_parts

    assert_includes parts[:html], 'Your extension request has been assessed'
    assert_includes parts[:text], 'Your extension request has been assessed'
  end
end
