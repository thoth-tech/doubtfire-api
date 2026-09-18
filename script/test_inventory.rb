#!/usr/bin/env ruby
# frozen_string_literal: true

# Build the canonical Minitest runnable inventory without executing the suite.
# CI compares this count with the sum reported by every shard, preventing a
# sharding change from appearing faster by silently filtering tests out.

require 'fileutils'

$LOAD_PATH.unshift(File.expand_path('../test', __dir__))
require_relative '../test/test_helper'
require_relative 'test_shard'

def fail_inventory(message)
  warn message
  $stdout.flush
  $stderr.flush
  exit! 1
end

inventory_path = ARGV.fetch(0) { fail_inventory 'Expected an inventory output path' }
repository_root = File.expand_path('..', __dir__)
test_root = File.join(repository_root, 'test')
Minitest.seed = 1
preloaded_runnables = Minitest::Runnable.runnables.dup

begin
  TestShard::SPLIT_TEST_FILES.each_key do |relative_path|
    path = File.join(repository_root, relative_path)
    before = Minitest::Runnable.runnables.dup
    require path
    added_classes = Minitest::Runnable.runnables - before
    actual_selectors = added_classes.flat_map do |test_class|
      test_class.runnable_methods.map do |method_name|
        source_path, line_number = test_class.instance_method(method_name).source_location
        relative_source = source_path&.delete_prefix("#{repository_root}/")
        "#{relative_source}:#{line_number}"
      end
    end
    expected_selectors = TestShard.method_runnables(path, relative_path).map do |method|
      method.fetch(:runnable)
    end
    next if actual_selectors.sort == expected_selectors.sort &&
            actual_selectors.uniq.length == actual_selectors.length

    fail_inventory <<~MESSAGE
      Split-test selector mismatch for #{relative_path}.
      Expected from source: #{expected_selectors.sort.inspect}
      Actual Minitest runnables: #{actual_selectors.sort.inspect}
    MESSAGE
  end

  Dir.glob(File.join(test_root, '**', '*_test.rb')).each { |path| require path }
  suite_classes = Minitest::Runnable.runnables - preloaded_runnables
  suite_classes.select! { |test_class| test_class.is_a?(Class) && test_class < Minitest::Test }
  entries = suite_classes.flat_map do |test_class|
    class_name = test_class.name
    fail_inventory 'A concrete test class has no stable name' if class_name.to_s.empty?

    test_class.runnable_methods.map { |method_name| "#{class_name}##{method_name}" }
  end
  fail_inventory 'The test runnable inventory is empty' if entries.empty?
  fail_inventory 'The test runnable inventory contains duplicate identifiers' if entries.uniq.length != entries.length

  FileUtils.mkdir_p(File.dirname(inventory_path))
  File.write(inventory_path, "#{entries.sort.join("\n")}\n")
  puts "Inventoried #{entries.length} Minitest runnables."
  $stdout.flush
  exit! 0
rescue StandardError, ScriptError => e
  warn "Unable to build test runnable inventory: #{e.full_message}"
  $stdout.flush
  $stderr.flush
  exit! 1
end
