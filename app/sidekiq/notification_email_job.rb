# frozen_string_literal: true

class NotificationEmailJob
  include Sidekiq::Job

  # The queue carries only the stable Notification id. Message content,
  # recipient details and other student data remain in the database and are
  # loaded by the worker.
  #
  # Student facing email runs on its own queue so it does not wait behind a
  # multi minute PDF build or CSV export on the default queue. A worker has to
  # be listening on `mailers` for any of this to be picked up.
  sidekiq_options queue: :mailers, retry: 3

  sidekiq_retry_in do |_count, exception|
    # SMTP 5xx is a permanent refusal. Keep the job in Sidekiq's dead set
    # immediately; retrying cannot correct an invalid recipient.
    :kill if exception.is_a?(Net::SMTPFatalError) || exception.is_a?(Net::SMTPSyntaxError)
  end

  sidekiq_retries_exhausted do |job, exception|
    Notification.where(id: job['args'].first).where.not(email_delivery_state: %w[delivered suppressed throttled]).update_all( # rubocop:disable Rails/SkipsModelValidations
      email_delivery_state: 'failed', email_delivery_error_class: exception.class.name
    )
  end

  def perform(notification_id)
    # Email is queued after commit. A missing row was deleted while queued and
    # does not need another attempt.
    notification = Notification.find_by(id: notification_id)
    return if notification.nil?
    return if %w[delivered suppressed throttled failed].include?(notification.email_delivery_state)

    # The institutional address is always the primary delivery. If this fails,
    # raise so Sidekiq retries as before and do not mark an optional copy as a
    # substitute for the primary channel.
    delivery_error = nil
    notification.with_lock do
      return if %w[delivered suppressed throttled failed].include?(notification.email_delivery_state)

      # Recheck the preference and terminal state under the same lock, so a
      # concurrent opted-out worker cannot overwrite a completed delivery.
      unless NotificationsMailer.perform_deliveries &&
             NotificationService.deliver_to?(notification.user, notification.notification_type, channel: :email)
        notification.update!(email_delivery_state: 'suppressed')
        return
      end

      notification.update!(email_delivery_attempts: notification.email_delivery_attempts + 1)
      begin
        NotificationsMailer.single_notification(notification).deliver_now
        notification.update!(email_delivery_state: 'delivered', email_delivered_at: Time.current,
                             email_delivery_error_class: nil)
      rescue StandardError => e
        permanent = e.is_a?(Net::SMTPFatalError) || e.is_a?(Net::SMTPSyntaxError)
        notification.update!(email_delivery_state: permanent ? 'failed' : 'retrying',
                             email_delivery_error_class: e.class.name)
        Rails.logger.error({ event: 'notifications.email_failed', notification_id: notification.id,
                             error_class: e.class.name, permanent: permanent }.to_json)
        # Commit the audit state before Sidekiq sees the failure.
        delivery_error = e
      end
    end
    raise delivery_error if delivery_error

    begin
      # Everything from here is optional, including the lookup itself: a
      # database error on it must not make Sidekiq retry the primary message.
      additional = notification.user.additional_notification_email
      return unless additional&.verified?
      return if additional.email.casecmp?(notification.user.email)

      AdditionalNotificationEmailDeliveryJob.perform_async(
        notification.id,
        additional.id,
        additional.verification_version
      )
    rescue StandardError => e
      # The primary message has already been accepted. An optional destination
      # cannot make that delivery retry (and potentially duplicate). The copy
      # normally has its own retrying job; this branch is only a lookup or queue
      # hand-off failure. Log only class/user/record identifiers: never
      # address/content.
      AdditionalNotificationEmailService.audit_delivery_event(
        notification.user,
        'notification_copy_failed'
      )
      Rails.logger.error(
        "Additional notification copy queue failed for user_id=#{notification.user_id} " \
        "notification_id=#{notification.id}: #{e.class}"
      )
    end
  end
end
