require 'test_helper'

# MN-F01: storing a browser's push registration.
class PushSubscriptionsApiTest < ActiveSupport::TestCase
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

  def test_a_user_can_register_a_browser
    params = FactoryBot.attributes_for(:push_subscription)

    add_auth_header_for(user: @user)

    assert_difference 'PushSubscription.count', 1 do
      post '/api/push_subscriptions', params
    end

    assert_equal 201, last_response.status

    subscription = PushSubscription.last

    assert_equal @user, subscription.user
    assert_equal params[:endpoint], subscription.endpoint
  end

  def test_the_response_does_not_leak_the_browser_keys
    params = FactoryBot.attributes_for(:push_subscription)

    add_auth_header_for(user: @user)
    post '/api/push_subscriptions', params

    json = JSON.parse(last_response.body)

    assert_equal params[:endpoint], json['endpoint']
    assert_not json.key?('p256dh'), 'the browser public key must not be sent back'
    assert_not json.key?('auth'), 'the browser auth secret must not be sent back'
  end

  # Same params both times, so the endpoint has to be built once and reused. The
  # factory sequences it, so calling the factory twice would be a different
  # browser and this would test nothing.
  def test_registering_the_same_browser_twice_updates_instead_of_duplicating
    params = FactoryBot.attributes_for(:push_subscription)

    add_auth_header_for(user: @user)
    post '/api/push_subscriptions', params

    assert_no_difference 'PushSubscription.count' do
      post '/api/push_subscriptions', params.merge(p256dh: 'BRotatedPublicKey')
    end

    assert_equal 'BRotatedPublicKey', PushSubscription.last.p256dh
  end

  # Shared machine. The endpoint belongs to the browser, so the registration has
  # to move to whoever signed in last rather than blowing up on the unique index.
  def test_registering_a_browser_another_user_had_moves_it_across
    subscription = FactoryBot.create(:push_subscription, user: @other)

    add_auth_header_for(user: @user)

    assert_no_difference 'PushSubscription.count' do
      post '/api/push_subscriptions', subscription.slice(:endpoint, :p256dh, :auth)
    end

    assert_equal @user, subscription.reload.user
    assert_empty @other.push_subscriptions.reload
  end

  def test_a_user_only_sees_their_own_registrations
    mine = FactoryBot.create(:push_subscription, user: @user)
    FactoryBot.create(:push_subscription, user: @other)

    add_auth_header_for(user: @user)
    get '/api/push_subscriptions'

    assert_equal 200, last_response.status

    json = JSON.parse(last_response.body)

    assert_equal 1, json.length
    assert_equal mine.endpoint, json.first['endpoint']
  end

  def test_a_user_can_remove_their_own_registration
    subscription = FactoryBot.create(:push_subscription, user: @user)

    add_auth_header_for(user: @user)

    assert_difference 'PushSubscription.count', -1 do
      delete '/api/push_subscriptions', endpoint: subscription.endpoint
    end

    assert_equal 200, last_response.status
  end

  def test_a_user_cannot_remove_someone_elses_registration
    subscription = FactoryBot.create(:push_subscription, user: @other)

    add_auth_header_for(user: @user)

    assert_no_difference 'PushSubscription.count' do
      delete '/api/push_subscriptions', endpoint: subscription.endpoint
    end

    assert_equal 404, last_response.status
  end

  def test_an_unauthenticated_request_is_rejected
    clear_auth_header

    assert_no_difference 'PushSubscription.count' do
      post '/api/push_subscriptions', FactoryBot.attributes_for(:push_subscription)
    end

    assert_equal 419, last_response.status
  end

  def test_a_registration_missing_the_browser_keys_is_rejected
    add_auth_header_for(user: @user)

    assert_no_difference 'PushSubscription.count' do
      post '/api/push_subscriptions', FactoryBot.attributes_for(:push_subscription).except(:p256dh, :auth)
    end

    assert_equal 400, last_response.status
  end

  # Firefox and Safari endpoints run past the 255 characters a default string
  # column would give us. If this ever fails the migration has regressed.
  def test_a_long_endpoint_is_stored_whole
    long_endpoint = "https://updates.push.services.mozilla.com/wpush/v2/#{'a' * 300}"

    add_auth_header_for(user: @user)
    post '/api/push_subscriptions', FactoryBot.attributes_for(:push_subscription, endpoint: long_endpoint)

    assert_equal 201, last_response.status
    assert_equal long_endpoint, PushSubscription.last.endpoint
  end

  def test_deleting_the_user_deletes_their_registrations
    FactoryBot.create(:push_subscription, user: @user)

    assert_difference 'PushSubscription.count', -1 do
      @user.destroy!
    end
  end
end
