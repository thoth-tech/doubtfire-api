require 'test_helper'

class AuthenticationRefreshCookieTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::JsonHelper

  def app
    Rails.application
  end

  setup do
    Rack::Attack.reset!
  end

  def test_remembered_login_rotates_refresh_token_at_renewal_boundary
    travel_to Time.zone.parse('2026-08-28 12:00:00 UTC') do
      user = FactoryBot.create(:user)
      renewal_boundary = Time.zone.now + 12.hours
      old_token = user.generate_authentication_token!(
        expiry: renewal_boundary,
        token_type: :refresh_token
      )

      post_remembered_login(user)

      refresh_tokens = user.auth_tokens.where(token_type: :refresh_token).order(:id)
      new_token = refresh_tokens.last

      assert_equal 2, refresh_tokens.count
      assert_not_equal old_token.id, new_token.id
      assert_operator new_token.auth_token_expiry, :>, renewal_boundary
      assert_match(/refresh_token=#{new_token.authentication_token};/, last_response.cookies['refresh_token'].to_s)
    end
  end

  def test_remembered_login_reuses_refresh_token_outside_renewal_window
    travel_to Time.zone.parse('2026-08-28 12:00:00 UTC') do
      user = FactoryBot.create(:user)
      old_token = user.generate_authentication_token!(
        expiry: Time.zone.now + 12.hours + 1.second,
        token_type: :refresh_token
      )

      post_remembered_login(user)

      refresh_tokens = user.auth_tokens.where(token_type: :refresh_token).order(:id)

      assert_equal [old_token.id], refresh_tokens.pluck(:id)
      assert_match(/refresh_token=#{old_token.authentication_token};/, last_response.cookies['refresh_token'].to_s)
    end
  end

  def test_remembered_login_rotates_expired_refresh_token
    travel_to Time.zone.parse('2026-08-28 12:00:00 UTC') do
      user = FactoryBot.create(:user)
      old_token = user.generate_authentication_token!(
        expiry: Time.zone.now - 1.second,
        token_type: :refresh_token
      )

      post_remembered_login(user)

      refresh_tokens = user.auth_tokens.where(token_type: :refresh_token).order(:id)
      new_token = refresh_tokens.last

      assert_equal 2, refresh_tokens.count
      assert_not_equal old_token.id, new_token.id
      assert_operator new_token.auth_token_expiry, :>, Time.zone.now
      assert_match(/refresh_token=#{new_token.authentication_token};/, last_response.cookies['refresh_token'].to_s)
    end
  end

  private

  def post_remembered_login(user)
    post_json '/api/auth.json', {
      username: user.username,
      password: 'password',
      remember: true
    }

    assert_equal 201, last_response.status
  end
end
