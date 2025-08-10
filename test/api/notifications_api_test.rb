require 'test_helper'

class NotificationsApiTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper

  def app
    Rails.application
  end

  def setup
    @user = FactoryBot.create(:user)
    @notifications = FactoryBot.create_list(:notification, 3, user: @user)
    add_auth_header_for user: @user
  end

  def test_get_notifications
    get '/api/notifications'
    assert_equal 200, last_response.status
    body = last_response_body
    assert_equal 3, body.length
    assert body.first.key?('message')
  end

  def test_delete_single_notification
    note = @notifications.first
    delete "/api/notifications/#{note.id}"
    assert_equal 204, last_response.status
    assert_nil Notification.find_by(id: note.id)
  end

  def test_delete_all_notifications
    delete '/api/notifications'
    assert_equal 204, last_response.status
    assert_equal 0, Notification.where(user_id: @user.id).count
  end

  def test_get_notifications_limits_to_20
    # Create 25 notifications for the user
    FactoryBot.create_list(:notification, 25, user: @user)

    get '/api/notifications'
    assert_equal 200, last_response.status

    body = last_response_body
    assert_equal 20, body.length, 'Should only return the latest 20 notifications'

    # Verify notifications are ordered newest first by created_at (or id)
    first_received = body.first['id']
    last_received = body.last['id']
    assert first_received > last_received, 'Notifications should be ordered newest first'
  end
end
