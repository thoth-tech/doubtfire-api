require 'test_helper'

class AzureSmtpSenderTest < ActionMailer::TestCase
  HUMAN_SENDER = 'Tutor Example <tutor@example.edu>'.freeze
  VERIFIED_SENDER = 'OnTrack <noreply@ontrack.example>'.freeze
  Sender = Struct.new(:name)

  def test_non_production_communication_keeps_existing_from_header
    mail = communication_email

    assert_equal ['tutor@example.edu'], mail.from
    assert_nil mail.reply_to
  end

  def test_production_communication_uses_verified_from_and_human_reply_to
    with_production_sender do
      mail = communication_email

      assert_equal ['noreply@ontrack.example'], mail.from
      assert_equal ['tutor@example.edu'], mail.reply_to
    end
  end

  def test_production_system_mail_does_not_add_misleading_reply_to
    previous_error_recipient = Doubtfire::Application.config.email_errors_to
    Doubtfire::Application.config.email_errors_to = 'Operations <operations@example.edu>'

    with_production_sender do
      mail = ErrorLogMailer.error_message('test', 'test message', StandardError.new('test error'))

      assert_equal ['noreply@ontrack.example'], mail.from
      assert_nil mail.reply_to
    end
  ensure
    Doubtfire::Application.config.email_errors_to = previous_error_recipient
  end

  def test_production_mail_fails_closed_without_configured_sender
    with_production_sender(nil) do
      error = assert_raises(ArgumentError) { communication_email.message }

      assert_equal 'institution email_sender must be configured in production', error.message
    end
  end

  private

  def communication_email
    CommunicationsMailer.communication_email(
      to: 'Student Example <student@example.edu>',
      from: HUMAN_SENDER,
      subject: 'Test communication',
      body: 'Test body',
      recipient: nil,
      sender: Sender.new('Tutor Example'),
      unit: nil,
      rule: nil
    )
  end

  def with_production_sender(sender = VERIFIED_SENDER, &)
    institution = Doubtfire::Application.config.institution
    previous_sender = institution[:email_sender]
    production = ActiveSupport::EnvironmentInquirer.new('production')
    institution[:email_sender] = sender

    Rails.stub(:env, production, &)
  ensure
    institution[:email_sender] = previous_sender
  end
end
