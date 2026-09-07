require 'test_helper'
require 'minitest/mock'
require 'tempfile'

# EN-V08: OnTrack has no discussion booking record. This proposal notifies the
# student when a tutor raises the audio discussion request that exists today.
class NotificationDiscussionRequestTest < ActiveSupport::TestCase
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

  def delivered_body
    mail = ActionMailer::Base.deliveries.last
    return '' if mail.nil?

    mail.multipart? ? mail.parts.map { |part| part.body.decoded }.join("\n") : mail.body.decoded
  end

  def build_wav_upload
    sample_rate = 8_000
    samples = Array.new(800, 0).pack('s<*')
    header = [
      'RIFF', 36 + samples.bytesize, 'WAVE',
      'fmt ', 16, 1, 1, sample_rate, sample_rate * 2, 2, 16,
      'data', samples.bytesize
    ].pack('A4VA4A4VvvVVvvA4V')

    tempfile = Tempfile.new(['discussion-request', '.wav'])
    tempfile.binmode
    tempfile.write(header)
    tempfile.write(samples)
    tempfile.rewind

    {
      'filename' => 'discussion-request.wav',
      'type' => 'audio/wav',
      'tempfile' => tempfile
    }
  end

  def with_audio_uploads(count)
    uploads = Array.new(count) { build_wav_upload }
    yield uploads
  ensure
    uploads&.each do |upload|
      upload['tempfile'].close!
    rescue Errno::ENOENT
      upload['tempfile'].close
    end
  end

  def notification_target
    DiscussionComment.new(recipient: @student)
  end

  def test_multiple_audio_prompts_create_one_notification_after_upload
    discussion = nil

    with_audio_uploads(2) do |uploads|
      assert_difference 'Notification.count', 1 do
        discussion = @task.add_discussion_comment(@tutor, uploads)
      end
    end
    NotificationEmailJob.drain

    notification = Notification.recent_first.first

    assert discussion.persisted?
    assert_equal 2, discussion.number_of_prompts
    assert_equal @student, notification.user
    assert_equal 'feedback', notification.notification_type
    assert_equal 'discussion_request_created', notification.event
    assert_equal 'A discussion prompt is ready for you.', notification.message
    assert_valid_push_payload(
      notification,
      expected_link: "/projects/#{@project.id}/dashboard/#{@task_definition.abbreviation}/feedback"
    )

    # Email is queued rather than sent inline since EN-F03.
    NotificationEmailJob.drain
    assert_equal 1, ActionMailer::Base.deliveries.count
    assert_equal [@student.email], ActionMailer::Base.deliveries.last.to
  end

  def test_feedback_preference_suppresses_every_channel
    @student.update!(receive_feedback_notifications: false)

    assert_no_difference 'Notification.count' do
      @task.send(:notify_discussion_request_recipient, notification_target)
    end

    assert_empty ActionMailer::Base.deliveries
  end

  def test_email_uses_the_event_template_without_assessment_content
    private_task_name = 'PRIVATE-TASK-NAME-7429'
    private_unit_name = 'PRIVATE-UNIT-NAME-7429'
    private_tutor_name = 'PrivateTutor7429 SensitiveName7429'

    @task_definition.update!(name: private_task_name)
    @unit.update!(name: private_unit_name)
    @tutor.update!(first_name: 'PrivateTutor7429', last_name: 'SensitiveName7429')

    @task.send(:notify_discussion_request_recipient, notification_target)
    NotificationEmailJob.drain

    body = delivered_body

    assert_not_empty body, 'guard: the multipart email body must be readable'
    assert_includes body, 'The prompt is not included in this email'
    assert_includes body, 'feedback notifications are turned on'
    assert_not_includes body, private_task_name
    assert_not_includes body, private_unit_name
    assert_not_includes body, private_tutor_name
  end

  def test_failed_audio_attachment_does_not_send_a_notification
    invalid = Tempfile.new(['invalid-discussion-request', '.wav'])
    invalid.write('not audio')
    invalid.rewind
    upload = {
      'filename' => 'invalid-discussion-request.wav',
      'type' => 'audio/wav',
      'tempfile' => invalid
    }

    assert_no_difference 'Notification.count' do
      assert_raises RuntimeError do
        @task.add_discussion_comment(@tutor, [upload])
      end
    end

    assert_empty ActionMailer::Base.deliveries
  ensure
    invalid&.close!
  end

  def test_notification_failure_does_not_stop_the_request_being_created
    discussion = nil

    NotificationService.stub :notify, ->(**_kwargs) { raise StandardError, 'notification failed' } do
      with_audio_uploads(1) do |uploads|
        discussion = @task.add_discussion_comment(@tutor, uploads)
      end
    end

    assert_not_nil discussion
    assert discussion.persisted?
    assert_equal @student, discussion.recipient
  end
end
