require 'test_helper'

class NotificationTest < ActiveSupport::TestCase
  def test_the_factory_builds_a_valid_notification_for_every_category
    Notification::TYPES.each do |type|
      notification = FactoryBot.create(:notification, type.to_sym)

      assert notification.persisted?, "a #{type} notification did not save"
      assert_equal type, notification.notification_type
      assert_equal "#{type}_event", notification.event
      assert notification.message.present?
    end
  end

  def test_an_unread_notification_is_in_the_unread_scope
    notification = FactoryBot.create(:notification, :unread)

    assert_nil notification.read_at
    assert_not notification.read?
    assert_includes Notification.unread, notification
  end

  def test_a_read_notification_is_out_of_the_unread_scope
    notification = FactoryBot.create(:notification, :read)

    assert_not_nil notification.read_at
    assert notification.read?
    assert_not_includes Notification.unread, notification
  end
end
