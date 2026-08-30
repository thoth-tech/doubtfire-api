# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require Rails.root.join('script/test_shard').to_s

class TestShardTest < ActiveSupport::TestCase
  def test_build_is_deterministic_balanced_and_assigns_every_runnable_once
    Dir.mktmpdir do |test_root|
      line_counts = [90, 70, 50, 30, 20, 10]
      line_counts.each_with_index do |line_count, index|
        path = File.join(test_root, "file_#{index}_test.rb")
        File.write(path, "# test line\n" * line_count)
      end

      first = TestShard.build(test_root: test_root, shard_count: 3)
      second = TestShard.build(test_root: test_root, shard_count: 3)
      assigned_runnables = first.flat_map { |shard| shard.fetch(:runnables) }
      expected_runnables = TestShard.all_runnables(test_root: test_root)
      shard_weights = first.map { |shard| shard.fetch(:weight) }

      assert_equal first, second
      assert_equal expected_runnables, assigned_runnables.sort
      assert_equal expected_runnables.length, assigned_runnables.uniq.length
      assert(first.all? { |shard| shard.fetch(:runnables).any? })
      assert_operator shard_weights.max - shard_weights.min, :<=, line_counts.max / TestShard::DEFAULT_LINES_PER_SECOND
    end
  end

  def test_split_units_include_each_def_and_dsl_test_method_exactly_once
    Dir.mktmpdir do |repository_root|
      test_root = File.join(repository_root, 'test')
      path = File.join(test_root, 'models', 'task_test.rb')
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, <<~RUBY)
        class TaskTest
          def test_first
            assert true
          end

          test 'second test' do
            assert true
          end

          def helper_method
            :not_a_test
          end

          def test_third
            assert true
          end

          test('fourth test') do
            assert true
          end
        end
      RUBY

      units = TestShard.split_units(path, 'test/models/task_test.rb', 2)
      runnables = units.flat_map { |unit| unit.fetch(:runnables) }

      expected_runnables = %w[
        test/models/task_test.rb:2
        test/models/task_test.rb:6
        test/models/task_test.rb:14
        test/models/task_test.rb:18
      ]
      assert_equal expected_runnables.sort, runnables.sort
      assert_equal runnables.length, runnables.uniq.length
      assert(units.all? { |unit| unit.fetch(:runnables).any? })
    end
  end

  def test_split_units_reject_unsupported_dynamic_test_declarations
    Dir.mktmpdir do |repository_root|
      path = File.join(repository_root, 'test', 'models', 'task_test.rb')
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, <<~RUBY)
        class TaskTest
          define_method(:test_dynamic) do
            assert true
          end
        end
      RUBY

      _output, error = capture_io do
        assert_raises(SystemExit) do
          TestShard.method_runnables(path, 'test/models/task_test.rb')
        end
      end
      assert_includes error, 'Unsupported test declaration'
    end
  end

  def test_write_manifest_creates_an_exact_newline_delimited_file_list
    Dir.mktmpdir do |directory|
      manifest_path = File.join(directory, 'nested', 'shard-1.txt')
      selected_files = %w[test/api/projects_api_test.rb test/models/project_test.rb]

      TestShard.write_manifest(manifest_path, selected_files)

      assert_equal "#{selected_files.join("\n")}\n", File.read(manifest_path)
    end
  end

  def test_required_services_supports_file_and_file_line_runnables
    runnables = [
      'test/api/users_api_test.rb',
      'test/models/task_test.rb:254',
      'test/models/task_similarity_test.rb'
    ]
    services = TestShard.required_services(runnables)

    assert_equal({ texlive: true, jplag: true }, services)
    assert_equal({ texlive: false, jplag: false }, TestShard.required_services(['test/api/users_api_test.rb']))
  end

  def test_cache_writer_shards_select_first_shard_that_needs_each_service
    shards = [
      { runnables: ['test/api/users_api_test.rb'] },
      { runnables: ['test/models/task_test.rb:254'] },
      { runnables: ['test/models/task_similarity_test.rb'] }
    ]

    assert_equal({ texlive: 2, jplag: 3 }, TestShard.cache_writer_shards(shards))
  end

  def test_write_github_output_appends_boolean_service_flags
    Dir.mktmpdir do |directory|
      output_path = File.join(directory, 'github-output')
      File.write(output_path, "existing=value\n")

      TestShard.write_github_output(
        output_path,
        ['test/models/task_test.rb:254'],
        cache_writer_services: { texlive: true }
      )

      assert_equal <<~OUTPUT, File.read(output_path)
        existing=value
        needs_texlive=true
        writes_texlive_cache=true
        needs_jplag=false
        writes_jplag_cache=false
      OUTPUT
    end
  end

  def test_execution_runnables_stay_absolute_after_working_directory_changes
    Dir.mktmpdir do |repository_root|
      Dir.mktmpdir do |other_directory|
        runnables = Dir.chdir(other_directory) do
          TestShard.execution_runnables(
            ['test/api/auth_test.rb', 'test/models/task_test.rb:50'],
            repository_root: repository_root
          )
        end

        assert_equal [
          File.join(repository_root, 'test/api/auth_test.rb'),
          "#{File.join(repository_root, 'test/models/task_test.rb')}:50"
        ], runnables
      end
    end
  end

  def test_run_tests_writes_count_and_exact_runnable_identifiers
    Dir.mktmpdir do |directory|
      run_count_path = File.join(directory, 'shard-1.txt')
      executed_runnables_path = File.join(directory, 'shard-1-runnables.txt')
      calls = []
      runner = lambda do |runnables|
        calls << runnables
        [true, 2, %w[FirstTest#test_a SecondTest#test_b]]
      end

      TestShard.stub(:run_test_command, runner) do
        capture_io do
          TestShard.run_tests(
            ['test/api/auth_test.rb', 'test/models/task_test.rb:50'],
            repository_root: directory,
            run_count_path: run_count_path,
            executed_runnables_path: executed_runnables_path
          )
        end
      end

      assert_equal [[
        File.join(directory, 'test/api/auth_test.rb'),
        "#{File.join(directory, 'test/models/task_test.rb')}:50"
      ]], calls
      assert_equal "2\n", File.read(run_count_path)
      assert_equal <<~RUNNABLES, File.read(executed_runnables_path)
        FirstTest#test_a
        SecondTest#test_b
      RUNNABLES
    end
  end
end
