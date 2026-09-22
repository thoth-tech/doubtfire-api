# frozen_string_literal: true

require 'minitest/autorun'
require 'rubocop'

class RubocopConfigurationTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  CONFIG_PATH = File.join(ROOT, '.rubocop.yml')

  def test_test_sources_are_discovered_with_the_effective_configuration
    config_store = RuboCop::ConfigStore.new
    config_store.options_config = CONFIG_PATH
    targets = RuboCop::TargetFinder.new(config_store).target_files_in_dir(File.join(ROOT, 'test'))

    %w[test/api/auth_test.rb test/models/task_test.rb test/factories/users_factory.rb].each do |path|
      assert_includes targets, File.join(ROOT, path), "#{path} must be linted"
    end
  end

  def test_required_plugins_and_their_cops_are_loaded
    plugins = rubocop_config.loaded_plugins.map { |plugin| plugin.about.name }

    %w[rubocop-minitest rubocop-factory_bot].each do |plugin|
      assert_includes plugins, plugin
    end

    %w[Minitest/AssertEqual FactoryBot/CreateList].each do |cop|
      assert_includes RuboCop::Cop::Registry.global.names, cop
      assert rubocop_config.cop_enabled?(cop), "#{cop} must be enabled"
    end
  end

  def test_existing_production_cops_remain_enabled
    %w[Lint/UnusedBlockArgument Layout/SpaceInsideHashLiteralBraces Style/PercentLiteralDelimiters].each do |cop|
      assert rubocop_config.cop_enabled?(cop), "#{cop} must remain enabled for production code"
    end
  end

  def test_existing_production_complexity_limits_are_not_relaxed
    { 'Metrics/AbcSize' => 153, 'Metrics/MethodLength' => 140 }.each do |cop, maximum|
      assert rubocop_config.cop_enabled?(cop), "#{cop} must remain enabled for production code"
      assert_operator rubocop_config.for_cop(cop).fetch('Max'), :<=, maximum,
                      "#{cop} must retain its production limit"
    end
  end

  def test_existing_quoted_symbol_style_is_preserved
    assert rubocop_config.cop_enabled?('Style/QuotedSymbols')
    assert_equal 'double_quotes', rubocop_config.for_cop('Style/QuotedSymbols').fetch('EnforcedStyle')
  end

  private

  def rubocop_config
    @rubocop_config ||= RuboCop::ConfigLoader.configuration_from_file(CONFIG_PATH)
  end
end
