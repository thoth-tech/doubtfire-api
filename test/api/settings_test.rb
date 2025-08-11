require 'test_helper'
require 'json'

class SettingTest < ActiveSupport::TestCase
    include Rack::Test::Methods
    include TestHelpers::AuthHelper
    include TestHelpers::JsonHelper

    def app
        Rails.application
    end

    # Get config details requires authentication
    def test_get_config_details_requires_authentication
      get '/api/settings'
      assert_equal 401, last_response.status
    end

  # Get config details when authenticated
    def test_get_config_details
        add_auth_header_for(user: User.first)
        expected_product_name =  Doubtfire::Application.config.institution[:product_name]

        # Perform the GET
        get '/api/settings'

        returned_mes = last_response_body['externalName']

        # Check if the call succeeds
        assert_equal 200, last_response.status
        # Check returned details match as expected
        assert_equal expected_product_name, returned_mes
    end

    # Get privacy policy requires authentication
    def test_get_privacy_policy_requires_authentication
      get '/api/settings/privacy'
      assert_equal 401, last_response.status
    end

  # Get privacy policy details when authenticated
    def test_get_privacy_policy_details
        add_auth_header_for(user: User.first)
        expected_privacy = Doubtfire::Application.config.institution[:privacy]
        expected_plagiarism = Doubtfire::Application.config.institution[:plagiarism]

        # Perform the GET
        get '/api/settings/privacy'

        # Set two returned details
        returned_privacy = last_response_body['privacy']
        returned_plagiarism = last_response_body['plagiarism']

        # Check if the call succeeds
        assert_equal 200, last_response.status

        # Check returned details match as expected
        assert_equal expected_privacy, returned_privacy
        assert_equal expected_plagiarism, returned_plagiarism
    end
end
