# frozen_string_literal: true

# Shared by all event producers. Limits are deliberately conservative defaults;
# operators can change them through environment configuration after measurement.
class NotificationDeliveryPolicy
  def self.positive_integer(name, default)
    value = Integer(ENV.fetch(name, default.to_s), 10)
    raise ArgumentError, "#{name} must be a positive integer" unless value.positive?

    value
  end

  def self.fanout_allowed?(event:, trigger:, recipient_count:, allow_large_fanout: false)
    limit = positive_integer('DOUBTFIRE_NOTIFICATION_FANOUT_LIMIT', 500)
    return true if recipient_count <= limit

    allowed = allow_large_fanout == true
    Rails.logger.warn({ event: 'notifications.fanout_limit', notification_event: event,
                        trigger: trigger, recipient_count: recipient_count,
                        limit: limit, allowed: allowed }.to_json)
    allowed
  end

  # Called while holding the recipient row lock, so concurrent producers share
  # one quota. Throttled events remain visible in-app but send neither channel.
  def self.throttled?(user)
    limit = positive_integer('DOUBTFIRE_NOTIFICATION_RECIPIENT_LIMIT', 30)
    window = positive_integer('DOUBTFIRE_NOTIFICATION_RECIPIENT_WINDOW_SECONDS', 3600)
    # A locking read sees current rows even inside an older REPEATABLE READ
    # transaction snapshot (some producers already hold a project transaction).
    candidates = Notification.where(user_id: user.id).where('created_at >= ?', Time.current - window)
                             .where.not(email_delivery_state: 'throttled').select(:id).limit(limit)
    Notification.current_rows(candidates).length >= limit
  end
end
