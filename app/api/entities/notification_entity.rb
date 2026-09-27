module Entities
  class NotificationEntity < Grape::Entity
    expose :id
    expose :notification_type
    expose :event
    expose :message
    expose :link
    expose :read_at
    expose :created_at

    # Added after link, and never instead of it. A client that only knows link
    # keeps working. A newer client opens the exact page from these ids, and a
    # nil means the record is gone, so it can say so instead of opening a
    # blank page.
    Notification::TARGET_KEYS.each do |key|
      expose(key) { |notification, _options| notification.target_ids[key] }
    end
  end
end
