require 'test_helper'

class AdditionalNotificationEmailVerificationJobTest < ActiveSupport::TestCase
  setup do
    ActionMailer::Base.deliveries.clear
    @user = FactoryBot.create(:user, email: 'primary@example.edu')
    @record = AdditionalNotificationEmailService.request(
      user: @user,
      email: 'secondary@example.org'
    )
    AdditionalNotificationEmailVerificationJob.clear
  end

  def test_job_payload_contains_only_record_id_and_version
    jid = AdditionalNotificationEmailVerificationJob.perform_async(
      @record.id,
      @record.verification_version
    )
    job = AdditionalNotificationEmailVerificationJob.jobs.find { |candidate| candidate['jid'] == jid }

    assert_equal [@record.id, @record.verification_version], job['args']
    assert_not_includes job.to_json, @record.email
    assert_equal 'mailers', job['queue']
  end

  def test_pending_current_version_delivers_one_safe_verification_message
    assert_difference -> { ActionMailer::Base.deliveries.count }, 1 do
      AdditionalNotificationEmailVerificationJob.new.perform(
        @record.id,
        @record.verification_version
      )
    end

    mail = ActionMailer::Base.deliveries.last
    assert_equal [@record.email], mail.to
    assert_empty mail.cc.to_a
    assert_includes mail.body.encoded, '/verify_additional_email#token='
  end

  def test_stale_version_or_verified_record_does_not_send
    assert_no_difference -> { ActionMailer::Base.deliveries.count } do
      AdditionalNotificationEmailVerificationJob.new.perform(
        @record.id,
        @record.verification_version - 1
      )
    end

    @record.update!(verified_at: Time.current)
    assert_no_difference -> { ActionMailer::Base.deliveries.count } do
      AdditionalNotificationEmailVerificationJob.new.perform(
        @record.id,
        @record.verification_version
      )
    end
  end

  def test_a_removed_address_is_dropped_without_retrying
    AdditionalNotificationEmailService.remove(user: @user)

    assert_no_difference -> { ActionMailer::Base.deliveries.count } do
      AdditionalNotificationEmailVerificationJob.new.perform(
        @record.id,
        @record.verification_version
      )
    end
  end

  def test_expired_record_does_not_send
    @record.update!(verification_expires_at: 1.minute.ago)

    assert_no_difference -> { ActionMailer::Base.deliveries.count } do
      AdditionalNotificationEmailVerificationJob.new.perform(
        @record.id,
        @record.verification_version
      )
    end
  end

  def test_a_rejected_verification_email_is_retried_without_the_address_in_the_error
    rejection = Class.new do
      def deliver_now
        raise '550 5.1.1 <secondary@example.org>: Recipient address rejected'
      end
    end.new

    error = AdditionalNotificationEmailMailer.stub(:verification, ->(_record) { rejection }) do
      assert_raises(AdditionalNotificationEmailService::DeliveryFailed) do
        AdditionalNotificationEmailVerificationJob.new.perform(
          @record.id,
          @record.verification_version
        )
      end
    end

    assert_not_includes error.message, @record.email
    assert_nil error.cause
  end

  def test_audit_store_failure_does_not_retry_an_accepted_verification_email
    AdditionalNotificationEmailService.stub(:audit!, ->(*) { raise 'audit unavailable' }) do
      assert_difference -> { ActionMailer::Base.deliveries.count }, 1 do
        AdditionalNotificationEmailVerificationJob.new.perform(
          @record.id,
          @record.verification_version
        )
      end
    end
  end
end
