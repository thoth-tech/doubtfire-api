# frozen_string_literal: true

require 'test_helper'

class NotificationDeliveryPolicyTest < ActiveSupport::TestCase
  def with_limits
    names = %w[DOUBTFIRE_NOTIFICATION_FANOUT_LIMIT DOUBTFIRE_NOTIFICATION_RECIPIENT_LIMIT DOUBTFIRE_NOTIFICATION_RECIPIENT_WINDOW_SECONDS]
    previous = names.index_with { |name| ENV.fetch(name, nil) }
    ENV[names[0]] = '2'
    ENV[names[1]] = '2'
    ENV[names[2]] = '3600'
    yield
  ensure
    previous.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
  end

  def test_fanout_boundary_and_explicit_override
    with_limits do
      [1, 2].each do |count|
        assert NotificationDeliveryPolicy.fanout_allowed?(event: 'test', trigger: 'unit:1', recipient_count: count)
      end
      assert_not NotificationDeliveryPolicy.fanout_allowed?(event: 'test', trigger: 'unit:1', recipient_count: 3)
      assert NotificationDeliveryPolicy.fanout_allowed?(event: 'test', trigger: 'unit:1', recipient_count: 3, allow_large_fanout: true)
      assert_not NotificationDeliveryPolicy.fanout_allowed?(event: 'test', trigger: 'unit:1', recipient_count: 3, allow_large_fanout: 'true')
    end
  end

  def test_burst_preserves_in_app_notifications_without_external_delivery
    user = FactoryBot.create(:user)
    with_limits do
      notifications = 3.times.map do
        NotificationService.notify(user: user, type: 'general', event: 'burst', message: 'Safe test message')
      end
      assert_equal %w[pending pending throttled], notifications.map(&:email_delivery_state)
      assert_nil notifications.last.delivered_at
      assert_equal 2, NotificationEmailJob.jobs.size
      assert_equal 2, PushNotificationDeliveryJob.jobs.size
      assert_equal 3, Notification.where(user: user, event: 'burst').count

      travel 3601.seconds do
        notification = NotificationService.notify(user: user, type: 'general', event: 'later', message: 'Later')
        assert_equal 'pending', notification.email_delivery_state
      end
    end
  end

  def test_deduplication_does_not_consume_another_quota_slot
    user = FactoryBot.create(:user)
    with_limits do
      twice = 2.times.map do
        NotificationService.notify(user: user, type: 'general', event: 'same', message: 'Same', dedupe_key: 'same')
      end
      assert_equal twice.first.id, twice.last.id
      assert_not NotificationDeliveryPolicy.throttled?(user)
    end
  end
end
