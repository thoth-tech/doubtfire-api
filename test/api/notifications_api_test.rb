require 'test_helper'

# EN-T02: the notifications API endpoints in app/api/notifications_api.rb.
#
# Five routes:
#   GET    /api/notifications                (list, optional unread_only)
#   GET    /api/notifications/unread_count
#   PUT    /api/notifications/:id/read
#   PUT    /api/notifications/read_all
#   DELETE /api/notifications/:id
#
# Every route scopes through current_user.notifications, so one user can never
# touch another's notifications. That is the case worth proving.
#
# Run this file on its own, not the whole suite: the test database is the
# development database (DF_TEST_DB_DATABASE == doubtfire-dev), so a full run
# holds locks and rewrites seeded data. See item 11 in
# doubtfire-deploy/RUNNING-LOCALLY.md.
class NotificationsApiTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper

  def app
    Rails.application
  end

  setup do
    @user = FactoryBot.create(:user, :student)
    @other = FactoryBot.create(:user, :student)
  end

  # GET /api/notifications ----------------------------------------------------

  def test_list_returns_the_users_notifications_newest_first
    older = FactoryBot.create(:notification, user: @user, created_at: 2.days.ago)
    newer = FactoryBot.create(:notification, user: @user, created_at: 1.hour.ago)
    FactoryBot.create(:notification, user: @other) # must not appear

    add_auth_header_for(user: @user)
    get '/api/notifications'

    assert_equal 200, last_response.status

    json = JSON.parse(last_response.body)
    ids = json.map { |n| n['id'] }

    assert_equal 2, json.length, 'only the current user\'s notifications'
    assert_equal [newer.id, older.id], ids, 'recent_first order'
  end

  def test_list_unread_only_filters_out_read_notifications
    unread = FactoryBot.create(:notification, user: @user)
    FactoryBot.create(:notification, :read, user: @user)

    add_auth_header_for(user: @user)
    get '/api/notifications', unread_only: true

    assert_equal 200, last_response.status

    json = JSON.parse(last_response.body)

    assert_equal 1, json.length
    assert_equal unread.id, json.first['id']
  end

  # GET /api/notifications/unread_count ---------------------------------------

  def test_unread_count_counts_only_the_users_unread
    FactoryBot.create_list(:notification, 2, user: @user)          # unread
    FactoryBot.create(:notification, :read, user: @user)          # read, excluded
    FactoryBot.create(:notification, user: @other)               # other user, excluded

    add_auth_header_for(user: @user)
    get '/api/notifications/unread_count'

    assert_equal 200, last_response.status
    assert_equal 2, JSON.parse(last_response.body)['count']
  end

  # PUT /api/notifications/:id/read -------------------------------------------

  def test_marking_a_notification_as_read
    notification = FactoryBot.create(:notification, user: @user)

    add_auth_header_for(user: @user)
    put "/api/notifications/#{notification.id}/read"

    assert_equal 200, last_response.status
    assert_not_nil JSON.parse(last_response.body)['read_at']
    assert_not_nil notification.reload.read_at
  end

  # PUT /api/notifications/read_all -------------------------------------------

  def test_marking_all_as_read_clears_only_the_users_unread
    FactoryBot.create_list(:notification, 3, user: @user)
    others = FactoryBot.create(:notification, user: @other)

    add_auth_header_for(user: @user)
    put '/api/notifications/read_all'

    assert_equal 200, last_response.status
    assert JSON.parse(last_response.body)['success']
    assert_equal 0, @user.notifications.unread.count
    assert_nil others.reload.read_at, 'another user\'s notifications are untouched'
  end

  # DELETE /api/notifications/:id ---------------------------------------------

  def test_deleting_a_notification
    notification = FactoryBot.create(:notification, user: @user)

    add_auth_header_for(user: @user)

    assert_difference 'Notification.count', -1 do
      delete "/api/notifications/#{notification.id}"
    end

    assert_equal 200, last_response.status
  end

  # Cross-user isolation ------------------------------------------------------

  def test_a_user_cannot_mark_another_users_notification_as_read
    theirs = FactoryBot.create(:notification, user: @other)

    add_auth_header_for(user: @user)
    put "/api/notifications/#{theirs.id}/read"

    assert_equal 404, last_response.status
    assert_nil theirs.reload.read_at, 'it must stay unread'
  end

  def test_a_user_cannot_delete_another_users_notification
    theirs = FactoryBot.create(:notification, user: @other)

    add_auth_header_for(user: @user)

    assert_no_difference 'Notification.count' do
      delete "/api/notifications/#{theirs.id}"
    end

    assert_equal 404, last_response.status
  end

  # Authentication ------------------------------------------------------------

  def test_an_unauthenticated_request_is_rejected
    clear_auth_header

    get '/api/notifications'

    assert_equal 419, last_response.status
  end
end
