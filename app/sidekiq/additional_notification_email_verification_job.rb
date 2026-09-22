# frozen_string_literal: true

class AdditionalNotificationEmailVerificationJob
  include Sidekiq::Job

  # Keep verification secrets and addresses out of Redis. The worker loads the
  # current record and creates its short-lived signed token only while rendering
  # the email. A version mismatch makes a queued replacement/resend job stale.
  sidekiq_options queue: :mailers, retry: 3

  def perform(additional_notification_email_id, verification_version)
    # A removed address leaves nothing to verify, so do not retry.
    record = AdditionalNotificationEmail.find_by(id: additional_notification_email_id)
    return if record.nil?
    return unless record.pending?
    return if record.verification_expired?
    return unless record.verification_version == verification_version

    begin
      AdditionalNotificationEmailMailer.verification(record).deliver_now
    rescue StandardError => e
      Rails.logger.error(
        "Additional notification email verification delivery failed for user_id=#{record.user_id}: #{e.class}"
      )
      AdditionalNotificationEmailService.raise_sanitized_delivery_failure!(e)
    end
    AdditionalNotificationEmailService.audit_delivery_event(
      record.user,
      'verification_email_delivered'
    )
  end
end
