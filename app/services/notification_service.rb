# Central entry point for raising a notification.
#
# Creates the in-app record and fans out to the enabled delivery channels
# (email and push through Sidekiq). A single category toggle (the user's
# receive_*_notifications preference) gates every channel: if the category is
# off, the notification is suppressed entirely. Per-channel granularity
# (a type x channel matrix) is deferred to a future iteration.
#
# Usage:
#   NotificationService.notify(
#     user: project.student,
#     type: 'feedback',
#     event: 'task_comment_created',
#     message: "New feedback is ready for #{task_definition.name}.",
#     link: "/#/projects/#{project.id}"
#   )
class NotificationService
  # Raise a notification for a user. Returns the created Notification, or nil if
  # the user's preference suppresses this category.
  #
  # type  - the category the user's preference switches on, one of
  #         Notification::TYPES.
  # event - the specific thing that happened, e.g. 'task_comment_created'.
  #         Required, so every notification can be traced back to its source.
  def self.notify(user:, type:, event:, message:, link: nil, dedupe_key: nil)
    notification = reserve(
      user: user,
      type: type,
      event: event,
      message: message,
      link: link,
      dedupe_key: dedupe_key
    )

    deliver(notification)
  end

  # Persist a notification without running its delivery channels. Callers that
  # need a short eligibility lock can commit this reservation, release the
  # lock, and then call `deliver` without holding a row lock across network I/O.
  def self.reserve(user:, type:, event:, message:, link: nil, dedupe_key: nil)
    type = type.to_s
    return nil unless deliver_to?(user, type)

    create_notification(
      user: user,
      notification_type: type,
      event: event.to_s,
      message: message,
      link: link,
      dedupe_key: dedupe_key
    )
  end

  def self.deliver(notification)
    return nil if notification.nil?

    # Concurrent or retried fan-outs can reserve the same immutable event. A
    # lock on that notification (not on the student's project) serializes only
    # its push hand-off. Email is queued once by Notification's after_commit
    # hook, so it cannot be consumed before an enclosing transaction commits
    # and a dedupe retry cannot queue it twice. delivered_at tracks the async
    # push hand-off; a failed hand-off stays retryable.
    notification.with_lock do
      unless notification.delivered_at?
        push_queued = queue_push(notification)
        notification.update!(delivered_at: Time.current) if push_queued
      end
    end

    notification
  end

  # Whether the user's category preference allows this notification type.
  def self.deliver_to?(user, type)
    pref = Notification::PREFERENCE_FOR_TYPE[type.to_s]
    return true if pref.nil? # types without a preference are always sent

    user.public_send(pref)
  end

  # A non-null dedupe key is an immutable event identity. The unique database
  # index makes concurrent fan-out jobs race safely: exactly one insert wins,
  # and only that winner runs the after_commit hook that queues the email.
  def self.create_notification(**attributes)
    Notification.transaction(requires_new: true) do
      Notification.create!(**attributes)
    end
  rescue ActiveRecord::RecordNotUnique
    raise if attributes[:dedupe_key].blank?

    Notification.find_by!(
      user: attributes.fetch(:user),
      dedupe_key: attributes.fetch(:dedupe_key)
    )
  end
  private_class_method :create_notification

  # Email channel. Called from Notification's after_commit hook, never directly
  # from notify or deliver, so the notification is committed before the job exists.
  #
  # Queue only the stable Notification id; message content, recipient details
  # and other student data remain in the database. Queue connection errors are
  # best-effort so the in-app record and push delivery are not blocked. Delivery
  # failures are raised by the job for Sidekiq to retry.
  def self.queue_email(notification)
    NotificationEmailJob.perform_async(notification.id)
  rescue StandardError => e
    Rails.logger.error(
      "Failed to queue notification email for Notification #{notification.id}: #{e.class}"
    )
    false
  end

  # Push channel. Queue only the stable Notification id so no student or
  # notification content is copied into Redis. A failed hand-off leaves
  # delivered_at unset, allowing the existing availability retry to try the
  # push hand-off again without duplicating the after-commit email.
  def self.queue_push(notification)
    PushNotificationDeliveryJob.perform_async(notification.id)
  rescue StandardError => e
    Rails.logger.error(
      "Failed to queue notification push for Notification #{notification.id}: #{e.class}"
    )
    false
  end
  private_class_method :queue_push
end
