require 'test_helper'
require 'uri'

class AuthenticationCallbackSecurityTest < ActiveSupport::TestCase
  test 'one-time credentials are encoded in a fragment rather than a query' do
    url = AuthenticationHelpers.frontend_sign_in_url(
      host: 'https://ontrack.example.edu/',
      auth_token: 'token+with/?reserved=characters',
      username: 'student+alias@example.edu'
    )
    parsed = URI.parse(url)
    callback = URI.decode_www_form(parsed.fragment).to_h

    assert_equal 'https', parsed.scheme
    assert_equal 'ontrack.example.edu', parsed.host
    assert_equal '/sign_in', parsed.path
    assert_nil parsed.query
    assert_equal 'token+with/?reserved=characters', callback.fetch('authToken')
    assert_equal 'student+alias@example.edu', callback.fetch('username')
  end

  test 'sensitive callback and request parameters are filtered' do
    filtered = Rails.application.config.filter_parameters.map(&:to_s)

    %w[
      authToken
      auth_token
      ltiToken
      lti_token
      ltik
      password
      refresh_token
      SAMLResponse
    ].each do |parameter|
      assert_includes filtered, parameter
    end
  end

  test 'authentication helper source does not interpolate presented tokens into logs' do
    source = File.read(Rails.root.join('app/helpers/authentication_helpers.rb'))

    literal_interpolation = ['#', '{auth_param}'].join
    assert_equal false, source.include?(literal_interpolation)
  end
end
