require 'test_helper'
require 'cgi'
require 'minitest/mock'

# A student's extension request notifies whoever has to assess it, and only
# while it is still waiting on a person.
class NotificationExtensionRequestTest < ActiveSupport::TestCase
  include TestHelpers::PushNotificationHelper

  EXTENSION_REQUEST_TEXT =
    'Private reason for the extension that must stay inside OnTrack.'.freeze

  setup do
    ActionMailer::Base.deliveries.clear
    NotificationEmailJob.clear

    @project = FactoryBot.create(:project)
    @unit = @project.unit
    @task_definition = @unit.task_definitions.first
    # Leave room for a one week extension before the due date.
    @task_definition.update!(due_date: @task_definition.target_date + 2.weeks)
    @task = @project.task_for_task_definition(@task_definition)
    @student = @project.student
    @convenor = @unit.main_convenor_user

    # Leave the request for a person to assess unless a test says otherwise.
    @unit.update!(auto_apply_extension_before_deadline: false)
  end

  # Without a tutorial, tutor_for falls back to the main convenor, so give the
  # student a tutor of their own when a test needs the two to differ.
  def give_the_student_a_tutor
    tutor_role = @unit.employ_staff(FactoryBot.create(:user, :tutor), Role.tutor)
    @project.enrol_in(FactoryBot.create(:tutorial, unit: @unit, campus: @project.campus, unit_role: tutor_role))
    ActionMailer::Base.deliveries.clear
    NotificationEmailJob.clear

    tutor_role.user
  end

  def request_extension(by_user: @student)
    @task.apply_for_extension(by_user, EXTENSION_REQUEST_TEXT, 1)
  end

  def extension_requests
    Notification.where(event: 'extension_requested')
  end

  def delivered_parts
    mail = ActionMailer::Base.deliveries.last

    {
      html: mail&.html_part&.body&.decoded.to_s,
      text: mail&.text_part&.body&.decoded.to_s
    }
  end

  def test_a_student_request_notifies_their_tutor
    tutor = give_the_student_a_tutor
    extension = nil

    assert_difference 'Notification.count', 1 do
      extension = request_extension
    end
    NotificationEmailJob.drain

    notification = Notification.recent_first.first
    product_name = Doubtfire::Application.config.institution[:product_name]
    expected_message = "#{@student.name} asked for an extension on #{@task_definition.name} in #{product_name}."

    assert_not extension.assessed?, 'guard: the request must still be waiting on a person'
    assert_equal tutor, notification.user
    assert_equal 'task', notification.notification_type
    assert_equal 'extension_requested', notification.event
    assert_equal expected_message, notification.message
    assert_equal extension, notification.notifiable

    push = assert_valid_push_payload(
      notification,
      expected_link: "/projects/#{@project.id}/dashboard/#{@task_definition.abbreviation}",
      expected_body: 'A student asked for an extension.'
    )
    assert_not_includes push['body'], EXTENSION_REQUEST_TEXT

    assert_equal 1, ActionMailer::Base.deliveries.count
    assert_equal [tutor.email], ActionMailer::Base.deliveries.last.to

    parts = delivered_parts

    parts.each_value do |body|
      assert_not_empty body
      assert_includes body, "Hi #{tutor.first_name}"
      assert_includes body, notification.link
      assert_includes body, '/edit_profile'
      assert_not_includes body, EXTENSION_REQUEST_TEXT
    end

    assert_includes parts[:text], expected_message
    assert_includes parts[:html], CGI.escapeHTML(expected_message)
  end

  def test_with_no_tutor_the_request_goes_to_the_main_convenor
    assert_equal @convenor, @project.tutor_for(@task_definition), 'guard: the student must have no tutor'

    assert_difference 'Notification.count', 1 do
      request_extension
    end

    notification = Notification.recent_first.first

    assert_equal 'extension_requested', notification.event
    assert_equal @convenor, notification.user
  end

  # The request is a task notification so the tutor's "Task notifications"
  # switch governs it. Turned off, nothing is created, emailed or pushed.
  def test_a_tutor_with_task_notifications_off_gets_no_email_or_push
    tutor = give_the_student_a_tutor
    tutor.update!(receive_task_notifications: false)
    PushNotificationDeliveryJob.clear

    assert_no_difference 'Notification.count' do
      request_extension
    end
    NotificationEmailJob.drain

    assert_empty ActionMailer::Base.deliveries
    assert_empty PushNotificationDeliveryJob.jobs
  end

  # The convenor is not the student's tutor here, so the rule against notifying
  # yourself is not what stops it. The extension is assessed on the spot; the
  # next test covers the student-only check for when that assessment fails.
  def test_an_extension_created_by_staff_does_not_notify_the_tutor
    tutor = give_the_student_a_tutor
    extension = nil

    assert_no_difference -> { extension_requests.count } do
      extension = request_extension(by_user: @convenor)
    end

    assert extension.assessed?, 'guard: staff extensions are assessed as they are made'
    assert_empty tutor.notifications
  end

  # A staff extension that cannot be applied is left unassessed, and it still
  # must not reach the tutor as a request from the student.
  def test_a_staff_extension_that_cannot_be_applied_does_not_notify_the_tutor
    tutor = give_the_student_a_tutor
    extension = nil

    @task.stub :grant_extension, false do
      assert_no_difference -> { extension_requests.count } do
        extension = request_extension(by_user: @convenor)
      end
    end

    assert_not extension.assessed?, 'guard: the failed grant must leave it unassessed'
    assert_empty tutor.notifications
  end

  def test_an_automatically_approved_request_does_not_notify_the_tutor
    @unit.update!(auto_apply_extension_before_deadline: true)
    tutor = give_the_student_a_tutor
    extension = nil

    assert_no_difference -> { extension_requests.count } do
      extension = request_extension
    end

    assert extension.assessed?, 'guard: the unit must have approved it already'
    assert extension.extension_granted
    assert_empty tutor.notifications
  end

  # If the automatic approval cannot be applied the request is left waiting,
  # so somebody still has to hear about it.
  def test_a_failed_automatic_approval_still_notifies_the_tutor
    @unit.update!(auto_apply_extension_before_deadline: true)
    tutor = give_the_student_a_tutor
    extension = nil

    @task.stub :grant_extension, false do
      assert_difference -> { extension_requests.count }, 1 do
        extension = request_extension
      end
    end

    assert_not extension.assessed?
    assert_equal tutor, extension_requests.last.user
  end

  def test_a_notification_failure_does_not_lose_the_request
    extension = nil
    calls = 0
    exploding_notify = lambda do |**_kwargs|
      calls += 1
      raise StandardError, 'notification exploded'
    end

    NotificationService.stub :notify, exploding_notify do
      extension = request_extension
    end

    assert_equal 1, calls, 'guard: the notification has to have been attempted'
    assert extension.persisted?, 'the extension request must still be saved'
    assert_not extension.assessed?
  end
end
