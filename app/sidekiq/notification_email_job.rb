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

  def perform(notification_id)
    # A producer may enqueue from inside a wider database transaction. Raising
    # on a not-yet-visible row makes Sidekiq retry after that transaction commits
    # instead of acknowledging and permanently dropping the delivery.
    notification = Notification.find(notification_id)

    # The category preference was checked when the notification was raised, but
    # a retried job can run hours later. Ask again so a preference the user has
    # switched off in the meantime stays off.
    return unless NotificationService.deliver_to?(notification.user, notification.notification_type)

    # The institutional address is always the primary delivery. If this fails,
    # raise so Sidekiq retries as before and do not mark an optional copy as a
    # substitute for the primary channel.
    NotificationsMailer.single_notification(notification).deliver_now

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
