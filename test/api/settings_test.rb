require 'test_helper'
require 'json'

class SettingsTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper

  def app
    Rails.application
  end

  def test_public_settings_are_available_without_authentication
    clear_auth_header

    get '/api/settings/public'

    assert_equal 200, last_response.status
    assert_equal(
      Doubtfire::Application.config.institution[:product_name],
      last_response_body['externalName']
    )
    assert_equal(
      Doubtfire::Application.config.institution[:has_logo],
      last_response_body['hasLogo']
    )
    assert_equal(
      Doubtfire::Application.config.institution[:logo_url],
      last_response_body['logoUrl']
    )
    assert_equal(
      Doubtfire::Application.config.institution[:logo_link_url],
      last_response_body['logoLinkUrl']
    )

    assert_equal(
      %w[externalName hasLogo logoLinkUrl logoUrl].sort,
      last_response_body.keys.sort
    )
  end

  def test_authenticated_settings_reject_unauthenticated_requests
    clear_auth_header

    get '/api/settings'

    assert_equal 419, last_response.status
    assert_equal(
      'No authentication details provided. Authentication is required to access this resource.',
      last_response_body['error']
    )
  end

  def test_authenticated_settings_are_available_with_authentication
    add_auth_header_for

    get '/api/settings'

    assert_equal 200, last_response.status
    assert_equal(
      Doubtfire::Application.config.overseer_enabled,
      last_response_body['overseerEnabled']
    )
    assert_equal TurnItIn.enabled?, last_response_body['tiiEnabled']
    assert_equal D2lIntegration.enabled?, last_response_body['d2lEnabled']

    assert_equal(
      %w[d2lEnabled overseerEnabled pushEnabled tiiEnabled vapidPublicKey].sort,
      last_response_body.keys.sort
    )
  end

  def test_privacy_policy_is_available_without_authentication
    clear_auth_header

    get '/api/settings/privacy'

    assert_equal 200, last_response.status
    assert_equal(
      Doubtfire::Application.config.institution[:privacy],
      last_response_body['privacy']
    )
    assert_equal(
      Doubtfire::Application.config.institution[:plagiarism],
      last_response_body['plagiarism']
    )

    assert_equal(
      %w[plagiarism privacy].sort,
      last_response_body.keys.sort
    )
  end
end
