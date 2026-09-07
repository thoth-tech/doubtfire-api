# frozen_string_literal: true

class PushNotificationDeliveryJob
  include Sidekiq::Job

  # Keep provider network I/O off `default`. The development stack cannot
  # safely consume that queue because it also contains submission/PDF jobs
  # whose supporting services are not present there.
  sidekiq_options queue: :notifications, retry: 3

  # Redis carries only the stable database id. The worker reloads the current
  # notification and subscription state immediately before delivery.
  def perform(notification_id)
    # A producer may enqueue from inside a wider database transaction. Raising
    # on a not-yet-visible row makes Sidekiq retry after that transaction commits
    # instead of acknowledging and permanently dropping the delivery.
    notification = Notification.find(notification_id)
    PushNotificationService.deliver(notification)
  end
end
