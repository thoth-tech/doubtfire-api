require 'test_helper'

class AdditionalNotificationEmailsApiTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper

  def app
    Rails.application
  end

  setup do
    @user = FactoryBot.create(:user, email: 'primary@example.edu')
    @other_user = FactoryBot.create(:user)
    add_auth_header_for(user: @user)
  end

  def test_current_user_can_request_read_and_remove_an_address
    put_json "/api/users/#{@user.id}/additional_notification_email", {
      email: 'secondary@example.org'
    }

    assert_equal 200, last_response.status
    assert_equal 'pending', last_response_body['status']
    assert_equal 'secondary@example.org', last_response_body['email']

    get "/api/users/#{@user.id}/additional_notification_email"
    assert_equal 200, last_response.status
    assert_equal 'private, no-store', last_response.headers['Cache-Control']

    delete "/api/users/#{@user.id}/additional_notification_email"
    assert_equal 204, last_response.status
    assert_nil @user.reload.additional_notification_email
  end

  def test_a_user_cannot_manage_another_users_destination
    put_json "/api/users/#{@other_user.id}/additional_notification_email", {
      email: 'secondary@example.org'
    }

    assert_equal 403, last_response.status
    assert_nil @other_user.reload.additional_notification_email
  end

  def test_public_verification_consumes_the_token_once
    record = AdditionalNotificationEmailService.request(
      user: @user,
      email: 'secondary@example.org'
    )
    token = record.verification_token
    clear_auth_header

    post_json '/api/additional_notification_emails/verify', { token: token }
    assert_equal 201, last_response.status
    assert_equal 'verified', last_response_body['status']

    post_json '/api/additional_notification_emails/verify', { token: token }
    assert_equal 409, last_response.status
  end

  def test_verification_token_is_filtered_from_server_logs
    assert_includes Rails.application.config.filter_parameters, :token
  end

  def test_rate_limit_returns_429_without_queueing_another_message
    put_json "/api/users/#{@user.id}/additional_notification_email", {
      email: 'secondary@example.org'
    }
    2.times do
      post_json "/api/users/#{@user.id}/additional_notification_email/resend", {}
    end
    queued = AdditionalNotificationEmailVerificationJob.jobs.count

    post_json "/api/users/#{@user.id}/additional_notification_email/resend", {}

    assert_equal 429, last_response.status
    assert_equal queued, AdditionalNotificationEmailVerificationJob.jobs.count
  end
end
