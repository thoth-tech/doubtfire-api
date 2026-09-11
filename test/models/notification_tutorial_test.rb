require 'test_helper'
require 'minitest/mock'

# EN-V04: notify only the affected student when an existing tutorial enrolment moves.
class NotificationTutorialTest < ActiveSupport::TestCase
  include TestHelpers::PushNotificationHelper

  setup do
    ActionMailer::Base.deliveries.clear
    NotificationEmailJob.clear

    @project = FactoryBot.create(:project)
    @unit = @project.unit
    @student = @project.student
    @old_tutorial = FactoryBot.create(
      :tutorial,
      unit: @unit,
      campus: @project.campus,
      abbreviation: 'OLD_TUT',
      meeting_day: 'Monday',
      meeting_time: '09:00'
    )
    @new_tutorial = FactoryBot.create(
      :tutorial,
      unit: @unit,
      campus: @project.campus,
      abbreviation: 'NEW_TUT',
      meeting_day: 'Tuesday',
      meeting_time: '14:30'
    )
  end

  def delivered_body
    mail = ActionMailer::Base.deliveries.last
    return '' if mail.nil?

    mail.multipart? ? mail.parts.map { |part| part.body.decoded }.join("\n") : mail.body.decoded
  end

  def test_moving_an_existing_enrolment_notifies_only_the_affected_student
    @project.enrol_in(@old_tutorial)
    other_project = FactoryBot.create(:project, unit: @unit, campus: @project.campus)

    ActionMailer::Base.deliveries.clear

    assert_difference 'Notification.count', 1 do
      @project.enrol_in(@new_tutorial)
    end
    NotificationEmailJob.drain

    notification = Notification.recent_first.first

    assert_equal @student, notification.user
    assert_not_equal other_project.student, notification.user
    assert_equal 'general', notification.notification_type
    assert_equal 'tutorial_changed', notification.event
    assert_equal 1, ActionMailer::Base.deliveries.count
    assert_equal [@student.email], ActionMailer::Base.deliveries.last.to
    assert_valid_push_payload(
      notification,
      expected_link: "/projects/#{@project.id}/dashboard",
      expected_body: 'Your tutorial details changed.'
    )
  end

  def test_message_and_templates_name_only_the_new_tutorial_schedule
    @project.enrol_in(@old_tutorial)

    ActionMailer::Base.deliveries.clear
    @project.enrol_in(@new_tutorial)
    NotificationEmailJob.drain

    notification = Notification.recent_first.first
    body = delivered_body

    assert_not_empty body, 'guard: the email body must be readable'

    [notification.message, body].each do |content|
      assert_includes content, @new_tutorial.abbreviation
      assert_includes content, @new_tutorial.meeting_day
      assert_includes content, @new_tutorial.meeting_time
      assert_not_includes content, @old_tutorial.abbreviation
      assert_not_includes content, @old_tutorial.meeting_day
      assert_not_includes content, @old_tutorial.meeting_time
    end

    mail = ActionMailer::Base.deliveries.last
    assert mail.multipart?
    assert_includes mail.parts.map(&:mime_type), 'text/plain'
    assert_includes mail.parts.map(&:mime_type), 'text/html'
    assert_includes body, 'Your tutorial has changed'
  end

  def test_first_tutorial_enrolment_does_not_notify
    assert_no_difference 'Notification.count' do
      @project.enrol_in(@new_tutorial)
    end

    assert_equal 0, ActionMailer::Base.deliveries.count
  end

  def test_selecting_the_same_tutorial_again_does_not_notify
    @project.enrol_in(@old_tutorial)

    ActionMailer::Base.deliveries.clear

    assert_no_difference 'Notification.count' do
      @project.enrol_in(@old_tutorial)
    end

    assert_equal 0, ActionMailer::Base.deliveries.count
  end

  def test_collapsing_multiple_stream_enrolments_does_not_notify
    stream_one = FactoryBot.create(:tutorial_stream, unit: @unit)
    stream_two = FactoryBot.create(:tutorial_stream, unit: @unit)
    streamed_tutorial_one = FactoryBot.create(
      :tutorial,
      unit: @unit,
      campus: @project.campus,
      tutorial_stream: stream_one
    )
    streamed_tutorial_two = FactoryBot.create(
      :tutorial,
      unit: @unit,
      campus: @project.campus,
      tutorial_stream: stream_two
    )

    @project.enrol_in(streamed_tutorial_one)
    @project.enrol_in(streamed_tutorial_two)
    assert_equal 2, @project.tutorial_enrolments.count

    ActionMailer::Base.deliveries.clear

    assert_no_difference 'Notification.count' do
      @project.enrol_in(@new_tutorial)
    end

    assert_equal [@new_tutorial], @project.reload.tutorial_enrolments.map(&:tutorial)
    assert_equal 0, ActionMailer::Base.deliveries.count
  end

  def test_notification_failure_does_not_stop_the_tutorial_move
    @project.enrol_in(@old_tutorial)

    NotificationService.stub :notify, ->(**_kwargs) { raise StandardError, 'notification failed' } do
      assert_nothing_raised do
        @project.enrol_in(@new_tutorial)
      end
    end

    assert_equal @new_tutorial, @project.reload.tutorial_enrolments.first.tutorial
  end
end
