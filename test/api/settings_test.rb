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
    assert_equal Doubtfire::Application.config.tutorial_enabled, last_response_body['tutorialEnabled']

    assert_equal(
      %w[d2lEnabled overseerEnabled pushEnabled tiiEnabled tutorialEnabled vapidPublicKey].sort,
      last_response_body.keys.sort
    )
  end

  def test_tutorial_flag_uses_the_existing_environment_parser
    original_env = ENV.fetch('TUTORIAL_ENABLED', nil)
    original_config = Doubtfire::Application.config.tutorial_enabled
    # Re-evaluate the boot assignment so this checks the real parser without
    # restarting Rails (and its database connections) for each value.
    assignment = Rails.root.join('config/application.rb').read.lines.find do |line|
      line.strip.start_with?('config.tutorial_enabled =')
    end
    assert assignment, 'tutorial rollout gate must be configured at boot'
    add_auth_header_for

    { nil => false, '' => false, '0' => false, 'false' => false,
      'FALSE' => false, 'true' => false, '1' => true, '2' => true }.each do |value, expected|
      ENV['TUTORIAL_ENABLED'] = value
      Doubtfire::Application.class_eval(assignment)

      get '/api/settings'

      assert_equal 200, last_response.status
      assert_equal expected, last_response_body['tutorialEnabled'], "TUTORIAL_ENABLED=#{value.inspect}"
    end
  ensure
    ENV['TUTORIAL_ENABLED'] = original_env
    Doubtfire::Application.config.tutorial_enabled = original_config
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
