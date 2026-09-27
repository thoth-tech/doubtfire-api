# frozen_string_literal: true

require 'test_helper'

class VapidConfigurationTest < ActiveSupport::TestCase
  def test_development_can_omit_push_but_production_cannot
    assert_nil VapidConfiguration.validate!(production: false, environment: {})
    error = assert_raises(ArgumentError) { VapidConfiguration.validate!(production: true, environment: {}) }
    assert_includes error.message, 'DOUBTFIRE_VAPID_PRIVATE_KEY'
  end

  def test_matching_keys_pass_and_mismatched_keys_fail_without_disclosing_values
    key = WebPush.generate_key
    environment = { 'DOUBTFIRE_VAPID_PUBLIC_KEY' => key.public_key, 'DOUBTFIRE_VAPID_PRIVATE_KEY' => key.private_key }
    VapidConfiguration.validate!(production: true, environment: environment)
    environment['DOUBTFIRE_VAPID_PRIVATE_KEY'] = WebPush.generate_key.private_key
    error = assert_raises(ArgumentError) { VapidConfiguration.validate!(production: true, environment: environment) }
    environment.each_value { |value| assert_not_includes error.message, value }
    assert_nil error.cause
  end

  def test_malformed_keys_fail_without_disclosing_values
    error = assert_raises(ArgumentError) do
      VapidConfiguration.validate!(production: true, environment: {
                                     'DOUBTFIRE_VAPID_PUBLIC_KEY' => 'malformed-public', 'DOUBTFIRE_VAPID_PRIVATE_KEY' => 'secret-marker'
                                   })
    end
    assert_not_includes error.message, 'secret-marker'
  end
end
