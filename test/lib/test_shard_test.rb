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

  def test_split_units_use_selector_runtime_weights
    Dir.mktmpdir do |repository_root|
      path = File.join(repository_root, 'test', 'models', 'task_test.rb')
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, <<~RUBY)
        class TaskTest
          def test_slow
            assert true
          end

          def test_fast_one
            assert true
          end

          def test_fast_two
            assert true
          end
        end
      RUBY
      relative_path = 'test/models/task_test.rb'
      selectors = TestShard.method_runnables(path, relative_path).map { |method| method.fetch(:runnable) }
      runtime_weights = selectors.zip([100.0, 1.0, 1.0]).to_h

      units = TestShard.split_units(path, relative_path, 2, runtime_weights: runtime_weights)

      assert_equal [2.0, 100.0], units.map { |unit| unit.fetch(:weight) }.sort
      assert_equal selectors.sort, units.flat_map { |unit| unit.fetch(:runnables) }.sort
    end
  end

  def test_hosted_runtime_weights_require_the_exact_selector_inventory
    Dir.mktmpdir do |test_root|
      4.times do |index|
        File.write(File.join(test_root, "file_#{index}_test.rb"), "# test line\n")
      end
      runnables = TestShard.all_runnables(test_root: test_root)
      profile = {
        selector_count: runnables.length,
        fingerprint: TestShard.runnable_profile_fingerprint(test_root: test_root, runnables: runnables),
        weights: [100.0, 3.0, 2.0, 1.0]
      }

      assert_equal(
        runnables.zip(profile.fetch(:weights)).to_h,
        TestShard.hosted_runtime_weights(test_root: test_root, runtime_profile: profile)
      )
      File.write(File.join(test_root, 'file_0_test.rb'), "# changed test source\n", mode: 'a')
      assert_empty(TestShard.hosted_runtime_weights(test_root: test_root, runtime_profile: profile))
      assert_empty(
        TestShard.hosted_runtime_weights(
          test_root: test_root,
          runtime_profile: profile.merge(fingerprint: '0' * 64, weights: [])
        )
      )
    end
  end

  def test_hosted_runtime_weights_reject_an_invalid_matching_profile
    Dir.mktmpdir do |test_root|
      File.write(File.join(test_root, 'file_test.rb'), "# test line\n")
      runnables = TestShard.all_runnables(test_root: test_root)
      profile = {
        selector_count: runnables.length,
        fingerprint: TestShard.runnable_profile_fingerprint(test_root: test_root, runnables: runnables),
        weights: [0.0]
      }

      error = assert_raises(SystemExit) do
        TestShard.hosted_runtime_weights(test_root: test_root, runtime_profile: profile)
      end

      assert_includes error.message, 'invalid weights'
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

  def test_image_build_targets_select_only_required_images_and_cache_writers
    shards = [
      { runnables: ['test/api/users_api_test.rb'] },
      { runnables: ['test/models/task_test.rb:254'] },
      { runnables: ['test/models/task_similarity_test.rb'] },
      { runnables: ['test/api/projects_api_test.rb'] },
      { runnables: ['test/models/task_test.rb:300'] }
    ]

    assert_equal(
      %w[api-cache-writer texlive-cache-writer jplag-cache-writer],
      TestShard.image_build_targets(
        shards: shards,
        logical_shards: [1, 2, 3],
        api_cache_writer: true
      )
    )
    assert_equal(
      %w[api texlive],
      TestShard.image_build_targets(
        shards: shards,
        logical_shards: [4, 5],
        api_cache_writer: false
      )
    )
    assert_equal(
      %w[api texlive jplag],
      TestShard.image_build_targets(
        shards: shards,
        logical_shards: [1, 2, 3],
        api_cache_writer: false,
        cache_write_enabled: false
      )
    )
  end

  def test_image_build_targets_have_one_cache_writer_per_scope_across_all_workers
    shards = TestShard.build(test_root: Rails.root.join('test'), shard_count: 20)
    workers = TestShard.worker_assignments(shards: shards, worker_count: 5)
    worker_targets = workers.each_with_index.map do |worker, index|
      TestShard.image_build_targets(
        shards: shards,
        logical_shards: worker.fetch(:shard_numbers),
        api_cache_writer: index.zero?
      )
    end
    all_targets = worker_targets.flatten

    assert(worker_targets.all? { |targets| targets.one? { |target| target.start_with?('api') } })
    %w[api-cache-writer texlive-cache-writer jplag-cache-writer].each do |writer|
      assert_equal 1, all_targets.count(writer), "expected exactly one #{writer}"
    end
  end

  def test_worker_assignments_balance_and_cover_every_logical_shard_once
    shards = [9, 8, 7, 6, 5, 4, 3, 2].map do |weight|
      { weight: weight.to_f, runnables: ["test_#{weight}"] }
    end

    first = TestShard.worker_assignments(shards: shards, worker_count: 2)
    second = TestShard.worker_assignments(shards: shards, worker_count: 2)
    assigned = first.flat_map { |worker| worker.fetch(:shard_numbers) }

    assert_equal first, second
    assert_equal (1..8).to_a, assigned.sort
    assert_equal assigned.length, assigned.uniq.length
    assert(first.all? { |worker| worker.fetch(:shard_numbers).length == 4 })
    assert_operator first.map { |worker| worker.fetch(:weight) }.max -
                    first.map { |worker| worker.fetch(:weight) }.min, :<=, 1.0
  end

  def test_worker_assignments_reject_an_uneven_physical_topology
    error = assert_raises(SystemExit) do
      TestShard.worker_assignments(
        shards: Array.new(6) { { weight: 1.0, runnables: ['test'] } },
        worker_count: 4
      )
    end

    assert_includes error.message, 'divisible'
  end

  def test_worker_assignments_use_a_matching_hosted_profile
    shards = Array.new(20) { |index| { weight: 1.0, runnables: ["test_#{index + 1}"] } }
    runtime_profile = {
      shard_count: 20,
      worker_count: 5,
      fingerprint: TestShard.shard_plan_fingerprint(shards),
      weights: [
        156.687, 118.980, 125.551, 125.041, 107.933,
        76.164, 113.087, 110.238, 175.824, 134.411,
        162.326, 139.937, 67.487, 71.771, 143.119,
        125.460, 113.024, 97.667, 145.716, 120.757
      ]
    }
    workers = TestShard.worker_assignments(shards: shards, worker_count: 5, runtime_profile: runtime_profile)

    assert_equal(
      [
        [4, 8, 9, 13],
        [11, 16, 17, 18],
        [1, 2, 3, 14],
        [6, 10, 19, 20],
        [5, 7, 12, 15]
      ],
      workers.map { |worker| worker.fetch(:shard_numbers) }
    )
  end

  def test_worker_assignments_ignore_a_stale_hosted_profile
    heavy_shards = [4, 8, 9, 13]
    shards = Array.new(20) do |index|
      weight = heavy_shards.include?(index + 1) ? 1000.0 : 1.0
      { weight: weight, runnables: ["test_#{index + 1}"] }
    end
    stale_profile = {
      shard_count: 20,
      worker_count: 5,
      fingerprint: '0' * 64,
      weights: Array.new(20, 1.0)
    }
    workers = TestShard.worker_assignments(shards: shards, worker_count: 5, runtime_profile: stale_profile)

    assert_equal 1, workers.map { |worker| (worker.fetch(:shard_numbers) & heavy_shards).length }.max
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
