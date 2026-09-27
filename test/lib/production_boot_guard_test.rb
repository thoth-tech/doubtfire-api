# frozen_string_literal: true

require 'minitest/autorun'
require 'active_support'
require 'active_support/test_case'
require 'active_support/core_ext/enumerable'
require 'open3'
require 'rbconfig'

class ProductionBootGuardTest < ActiveSupport::TestCase
  ROOT = File.expand_path('../..', __dir__)
  SECRET_KEYS = %w[DF_SECRET_KEY_BASE DF_SECRET_KEY_ATTR DF_SECRET_KEY_DEVISE].freeze
  BOOT_SCRIPT = <<~RUBY
    require 'rails/all'
    require 'dotenv'
    require 'dotenv/rails'

    # Exercise the real production application configuration with empty
    # encrypted credentials and no developer .env files. Only the synthetic
    # environment below supplies credentials; never read local secrets.
    Dotenv::Rails.files.clear
    class << Rails::Application
      def credentials
        @boot_guard_test_credentials ||= ActiveSupport::OrderedOptions.new
      end
    end

    begin
      require './config/application'
      puts 'Production configuration accepted'
    rescue RuntimeError => error
      warn error.message
      exit 1
    end
  RUBY

  def test_missing_attribute_key_reports_only_that_key_as_missing
    assert_missing_keys('DF_SECRET_KEY_ATTR')
  end

  def test_missing_devise_key_reports_only_that_key_as_missing
    assert_missing_keys('DF_SECRET_KEY_DEVISE')
  end

  def test_missing_base_key_reports_only_that_key_as_missing
    assert_missing_keys('DF_SECRET_KEY_BASE')
  end

  def test_all_missing_keys_are_reported_as_missing
    assert_missing_keys(*SECRET_KEYS)
  end

  def test_all_present_keys_pass_the_production_guard
    output, error, status = boot_configuration

    assert_predicate status, :success?, error
    assert_includes output, 'Production configuration accepted'
  end

  private

  def assert_missing_keys(*missing_keys)
    _output, error, status = boot_configuration(*missing_keys)

    assert_not_predicate status, :success?
    assert_includes error, 'Required keys are not set'
    SECRET_KEYS.each do |key|
      assert_match(/#{key}\s+=> #{!missing_keys.include?(key)}\b/, error)
      assert_not_includes error, "boot-guard-fixture-#{key}"
    end
  end

  def boot_configuration(*missing_keys)
    environment = ENV.keys.grep(/\ADF_|\ARAILS_MASTER_KEY\z/).index_with(nil)
    environment.merge!('RAILS_ENV' => 'production', 'DF_AUTH_METHOD' => 'database',
                       'OVERSEER_ENABLED' => 'false')
    SECRET_KEYS.each do |key|
      environment[key] = missing_keys.include?(key) ? nil : "boot-guard-fixture-#{key}"
    end

    Open3.capture3(environment, RbConfig.ruby, '-e', BOOT_SCRIPT, chdir: ROOT)
  end
end
