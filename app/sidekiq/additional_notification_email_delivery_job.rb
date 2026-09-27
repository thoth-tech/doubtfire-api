# frozen_string_literal: true

class AdditionalNotificationEmailDeliveryJob
  include Sidekiq::Job

  # This optional channel retries independently. Its failure can never cause a
  # successfully accepted institutional message to be sent again.
  sidekiq_options queue: :mailers, retry: 3

  def perform(notification_id, additional_notification_email_id, verification_version)
    # Either row can be deleted after queueing (the notification by delete-all,
    # the address by removal). Neither is a delivery failure, so do not retry
    # or record one.
    notification = Notification.find_by(id: notification_id)
    additional = AdditionalNotificationEmail.find_by(id: additional_notification_email_id)
    return if notification.nil? || additional.nil?

    return unless additional.user_id == notification.user_id
    return unless additional.verified?
    return unless additional.verification_version == verification_version
    return if additional.email.casecmp?(notification.user.email)
    return unless NotificationService.deliver_to?(
      notification.user,
      notification.notification_type,
      channel: :email
    )

    NotificationsMailer.additional_notification_copy(notification, additional.email).deliver_now
    AdditionalNotificationEmailService.audit_delivery_event(
      notification.user,
      'notification_copy_delivered'
    )
  rescue StandardError => e
    user_id = notification&.user_id
    if notification
      AdditionalNotificationEmailService.audit_delivery_event(
        notification.user,
        'notification_copy_failed'
      )
    end
    Rails.logger.error(
      "Additional notification copy failed for user_id=#{user_id || 'unknown'} " \
      "notification_id=#{notification_id}: #{e.class}"
    )
    # Retry as before, but without the original message, which for an SMTP
    # rejection usually quotes the additional address.
    AdditionalNotificationEmailService.raise_sanitized_delivery_failure!(e)
  end
end
