#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'digest'
require 'open3'

# Split the Rails test suite into deterministic, approximately even shards.
#
# Most files remain the atomic unit. The few files that have repeatedly taken
# several minutes in hosted CI are split into balanced groups of test methods,
# using Rails' supported file:line selector. This keeps every worker isolated
# while removing the longest single-file bottlenecks.
#
# Preview a shard without running Rails by passing --dry-run. Pass
# --list-runnables to print the canonical coverage manifest used by CI.
# Set TEST_SHARD_MANIFEST to write the selected runnable list and
# TEST_SHARD_GITHUB_OUTPUT to expose helper-service requirements to Actions.
module TestShard
  module_function

  DEFAULT_LINES_PER_SECOND = 20.0

  # These are the single-file bottlenecks observed in hosted runs. Splitting
  # only known bottlenecks keeps the plan maintainable while removing files
  # that would otherwise set the lower bound for the slowest shard.
  SPLIT_TEST_FILES = {
    'test/api/feedback/feedback_chip_api_consolidated_test.rb' => 2,
    'test/api/groups_api_test.rb' => 2,
    'test/api/peer_progress_api_test.rb' => 2,
    'test/api/tasks_api_test.rb' => 3,
    'test/api/tutorials_test.rb' => 3,
    'test/api/units/task_definitions_api_test.rb' => 3,
    'test/api/upload_security_test.rb' => 3,
    'test/models/task_test.rb' => 3,
    'test/models/unit_model_test.rb' => 3
  }.freeze

  # Source size is the fallback weight. These conservative hosted upper bounds
  # correct the largest known outliers where line count mispredicts runtime.
  FILE_RUNTIME_WEIGHTS = {
    'test/api/csv_test.rb' => 55.0,
    'test/api/feedback/feedback_chip_api_consolidated_test.rb' => 60.0,
    'test/api/groups_api_test.rb' => 70.0,
    'test/api/peer_progress_api_test.rb' => 90.0,
    'test/api/projects_api_test.rb' => 35.0,
    'test/api/tasks_api_test.rb' => 152.0,
    'test/api/tutorials_test.rb' => 100.0,
    'test/api/units/task_definitions_api_test.rb' => 151.0,
    'test/api/upload_security_test.rb' => 173.0,
    'test/config/deakin_config_test.rb' => 50.0,
    'test/models/notification_group_test.rb' => 30.0,
    'test/models/task_test.rb' => 210.0,
    'test/models/unit_model_test.rb' => 180.0,
    'test/sidekiq/send_due_soon_reminders_job_test.rb' => 75.0
  }.freeze

  SERVICE_TEST_FILES = {
    texlive: %w[
      test/api/projects_api_test.rb
      test/api/tasks_api_test.rb
      test/api/units/task_definitions_api_test.rb
      test/models/project_model_test.rb
      test/models/task_similarity_test.rb
      test/models/task_test.rb
      test/models/tii_model_test.rb
      test/models/unit_model_test.rb
    ].freeze,
    jplag: %w[
      test/models/task_similarity_test.rb
    ].freeze
  }.freeze

  # Hosted setup time paid once by each shard that needs a helper. Including
  # it in the greedy score keeps helper-backed tests together when doing so is
  # faster than starting another copy of the service.
  SERVICE_SETUP_WEIGHTS = {
    texlive: 25.0,
    jplag: 27.0
  }.freeze

  # Hosted Minitest timings for the exact sorted runnable inventory. Using
  # selector-level weights fixes the large skew that source size cannot
  # predict. Any inventory mismatch falls back to the conservative estimates.
  HOSTED_RUNNABLE_RUNTIME_PROFILE = {
    selector_count: 402,
    fingerprint: '741ba43118789cb114a817d7f17713558d6a9197b9b27ff16e94f7de2f43014b',
    weights: [
      2.74, 5.42, 2.69, 0.12, 1.06, 30.10, 21.80, 16.62,
      2.70, 35.88, 14.04, 10.22, 17.52, 2.76, 4.23, 1.43,
      4.34, 0.04, 0.04, 0.06, 0.75, 0.04, 0.04, 0.06,
      0.05, 0.04, 0.04, 0.06, 1.47, 35.98, 42.32, 4.47,
      3.87, 4.22, 4.68, 4.26, 4.02, 4.37, 3.90, 3.86,
      4.26, 22.90, 51.70, 4.64, 8.14, 5.90, 0.58, 0.62,
      0.61, 0.58, 0.63, 0.61, 0.58, 0.62, 0.60, 0.62,
      0.63, 0.62, 0.64, 0.60, 0.62, 0.60, 0.61, 0.87,
      0.82, 0.60, 0.60, 0.90, 0.61, 0.60, 0.62, 0.57,
      0.60, 0.64, 0.81, 0.62, 0.62, 0.60, 0.58, 0.60,
      0.60, 0.65, 0.60, 0.62, 0.64, 0.63, 0.64, 1.48,
      1.50, 0.59, 0.64, 0.56, 31.05, 6.25, 11.81, 0.08,
      0.05, 33.12, 20.60, 10.06, 8.46, 2.26, 2.26, 2.16,
      2.28, 1.46, 11.26, 2.72, 1.58, 6.30, 4.34, 4.44,
      4.72, 3.64, 5.78, 4.65, 24.18, 4.98, 20.36, 2.18,
      2.52, 3.20, 2.14, 2.22, 2.04, 2.20, 2.26, 2.44,
      2.46, 0.78, 47.32, 9.34, 3.22, 7.22, 6.38, 8.64,
      8.86, 8.48, 4.56, 4.48, 4.44, 4.57, 0.22, 4.26,
      4.23, 4.20, 1.06, 4.26, 4.26, 4.32, 4.24, 4.25,
      4.44, 4.31, 4.86, 4.33, 4.33, 4.40, 4.12, 4.50,
      4.54, 4.68, 4.29, 4.62, 8.86, 8.99, 8.63, 8.92,
      9.14, 8.57, 8.64, 7.04, 11.90, 3.08, 4.40, 4.14,
      4.50, 4.12, 4.22, 4.40, 0.06, 0.34, 0.04, 0.22,
      4.45, 15.84, 1.12, 1.30, 1.17, 1.20, 1.26, 1.28,
      1.98, 2.06, 3.28, 22.22, 1.88, 2.14, 2.26, 2.37,
      2.12, 2.23, 2.02, 2.10, 0.01, 0.01, 2.23, 2.04,
      0.01, 0.01, 0.02, 0.01, 0.01, 0.01, 2.25, 1.96,
      2.00, 0.02, 0.01, 0.01, 0.01, 0.02, 0.01, 0.01,
      2.18, 2.10, 2.09, 2.00, 1.96, 2.10, 1.90, 2.18,
      0.87, 8.53, 0.01, 47.11, 0.01, 0.01, 0.62, 19.13,
      0.30, 0.04, 5.54, 18.47, 0.10, 0.12, 0.54, 0.04,
      0.08, 0.94, 0.98, 4.66, 0.02, 9.63, 0.15, 2.68,
      1.18, 4.91, 60.17, 0.01, 5.11, 6.30, 35.49, 11.04,
      8.54, 8.98, 11.34, 7.56, 1.72, 6.88, 0.01, 18.04,
      0.06, 0.01, 12.70, 57.64, 0.04, 5.86, 0.10, 0.01,
      12.46, 10.00, 0.01, 20.75, 0.01, 8.72, 33.92, 31.71,
      1.10, 0.92, 33.32, 2.12, 1.18, 2.44, 2.56, 3.36,
      1.02, 2.38, 2.00, 2.14, 1.97, 2.41, 2.10, 1.00,
      1.92, 1.85, 2.20, 2.04, 2.10, 2.10, 0.91, 12.57,
      22.18, 1.08, 2.12, 11.26, 13.48, 15.02, 14.31, 1.00,
      48.98, 25.62, 0.95, 12.70, 13.78, 0.96, 13.68, 1.08,
      1.11, 1.66, 9.14, 17.96, 4.98, 0.01, 0.01, 17.82,
      4.44, 13.40, 0.40, 1.55, 0.35, 0.35, 2.84, 18.26,
      1.44, 2.26, 2.26, 1.66, 1.72, 1.24, 1.20, 2.36,
      0.44, 0.54, 0.31, 2.78, 0.60, 2.04, 2.26, 1.16,
      1.36, 1.16, 1.38, 1.56, 2.16, 1.54, 15.31, 9.02,
      3.20, 6.63, 3.76, 3.48, 0.65, 1.46, 1.06, 2.00,
      1.38, 1.40, 47.62, 2.18, 23.12, 0.03, 4.14, 17.76,
      0.07, 0.08, 7.68, 0.01, 0.10, 0.08, 8.98, 0.94,
      5.87, 1.44, 1.28, 0.06, 69.18, 8.36, 37.88, 11.08,
      0.08, 0.24
    ]
  }.freeze

  # Optional second-level profile for packing already-built logical shards
  # onto physical workers. The selector profile normally makes this redundant.
  HOSTED_SHARD_RUNTIME_PROFILE = {}.freeze

  TEST_METHOD_PATTERN = /^\s*(?:def\s+test_[A-Za-z0-9_!?=]*|test\s*(?:\(\s*)?['":])/
  TEST_DECLARATION_CANDIDATE_PATTERN = /^\s*(?:def\s+test_|test\b|define_method\b.*test_)/

  def repository_relative(path, test_root)
    path.delete_prefix("#{File.dirname(test_root)}/")
  end

  def method_runnables(path, relative_path)
    lines = File.readlines(path)
    starts = lines.each_index.with_object([]) do |index, result|
      line = lines[index]
      if line.match?(TEST_DECLARATION_CANDIDATE_PATTERN) && !line.match?(TEST_METHOD_PATTERN)
        abort "Unsupported test declaration in split test file #{relative_path}:#{index + 1}"
      end
      result << (index + 1) if line.match?(TEST_METHOD_PATTERN)
    end
    abort "No test methods found in split test file #{relative_path}" if starts.empty?

    weighted_methods = starts.each_with_index.map do |line_number, index|
      next_line = starts[index + 1] || (lines.length + 1)
      {
        runnable: "#{relative_path}:#{line_number}",
        line_count: next_line - line_number
      }
    end
    total_lines = weighted_methods.sum { |method| method.fetch(:line_count) }
    runtime_weight = file_weight(relative_path, lines.length)

    weighted_methods.each do |method|
      method[:weight] = runtime_weight * method.fetch(:line_count) / total_lines
    end
  end

  def file_weight(relative_path, line_count)
    FILE_RUNTIME_WEIGHTS.fetch(relative_path, line_count / DEFAULT_LINES_PER_SECOND)
  end

  def split_units(path, relative_path, part_count, runtime_weights: {})
    methods = method_runnables(path, relative_path).map do |method|
      method.merge(weight: runtime_weights.fetch(method.fetch(:runnable), method.fetch(:weight)))
    end
    abort "Cannot split #{relative_path} into #{part_count} non-empty parts" if part_count > methods.length

    parts = Array.new(part_count) { { weight: 0.0, line_count: 0, runnables: [] } }
    methods.sort_by { |method| [-method.fetch(:weight), method.fetch(:runnable)] }.each do |method|
      part_index = parts.each_index.min_by { |index| [parts[index][:weight], index] }
      parts[part_index][:runnables] << method.fetch(:runnable)
      parts[part_index][:weight] += method.fetch(:weight)
      parts[part_index][:line_count] += method.fetch(:line_count)
    end
    parts
  end

  def canonical_runnables(test_root:)
    test_files = Dir.glob(File.join(test_root, '**', '*_test.rb'))
    abort "No test files found under #{test_root}" if test_files.empty?

    test_files.sort.flat_map do |path|
      relative_path = repository_relative(path, test_root)
      part_count = SPLIT_TEST_FILES[relative_path]
      next method_runnables(path, relative_path).map { |method| method.fetch(:runnable) } if part_count

      relative_path
    end.sort
  end

  def runnable_profile_fingerprint(test_root:, runnables:)
    digest = Digest::SHA256.new
    digest << runnables.join("\0")
    Dir.glob(File.join(test_root, '**', '*'), File::FNM_DOTMATCH).select { |path| File.file?(path) }.sort.each do |path|
      relative_path = path.delete_prefix("#{test_root}/")
      digest << "\0#{relative_path}\0" << File.binread(path)
    end
    digest.hexdigest
  end

  def hosted_runtime_weights(test_root:, runtime_profile:)
    return {} if runtime_profile.empty?

    runnables = canonical_runnables(test_root: test_root)
    return {} unless runtime_profile.fetch(:selector_count, nil) == runnables.length
    fingerprint = runnable_profile_fingerprint(test_root: test_root, runnables: runnables)
    return {} unless runtime_profile.fetch(:fingerprint, nil) == fingerprint

    weights = runtime_profile.fetch(:weights, nil)
    valid_weights = weights.is_a?(Array) && weights.length == runnables.length && weights.all? do |weight|
      weight.is_a?(Numeric) && weight.positive? && (!weight.respond_to?(:finite?) || weight.finite?)
    end
    abort 'The hosted runnable runtime profile contains invalid weights' unless valid_weights

    runnables.zip(weights).to_h
  end

  def runnable_units(test_root:, runtime_profile: HOSTED_RUNNABLE_RUNTIME_PROFILE)
    runtime_weights = hosted_runtime_weights(test_root: test_root, runtime_profile: runtime_profile)

    Dir.glob(File.join(test_root, '**', '*_test.rb')).flat_map do |path|
      relative_path = repository_relative(path, test_root)
      part_count = SPLIT_TEST_FILES[relative_path]
      if part_count
        next split_units(path, relative_path, part_count, runtime_weights: runtime_weights)
      end

      line_count = File.foreach(path).count
      [{
        weight: runtime_weights.fetch(relative_path, file_weight(relative_path, line_count)),
        line_count: line_count,
        runnables: [relative_path]
      }]
    end
  end

  def all_runnables(test_root:)
    canonical_runnables(test_root: test_root)
  end

  def build(test_root:, shard_count:, runtime_profile: HOSTED_RUNNABLE_RUNTIME_PROFILE)
    units = runnable_units(test_root: test_root, runtime_profile: runtime_profile)
    abort "TEST_SHARD_COUNT cannot exceed the #{units.length} discovered runnable groups" if shard_count > units.length

    shards = Array.new(shard_count) do
      { weight: 0.0, line_count: 0, runnables: [], services: {} }
    end
    units.sort_by { |unit| [-unit.fetch(:weight), unit.fetch(:runnables).first] }.each do |unit|
      unit_services = required_services(unit.fetch(:runnables)).select { |_service, required| required }.keys
      shard_index = shards.each_index.min_by do |index|
        new_service_weight = unit_services.sum do |service|
          shards[index][:services][service] ? 0.0 : SERVICE_SETUP_WEIGHTS.fetch(service)
        end
        [shards[index][:weight] + new_service_weight, index]
      end
      shard = shards.fetch(shard_index)
      unit_services.each do |service|
        next if shard[:services][service]

        shard[:services][service] = true
        shard[:weight] += SERVICE_SETUP_WEIGHTS.fetch(service)
      end
      shard[:runnables].concat(unit.fetch(:runnables))
      shard[:weight] += unit.fetch(:weight)
      shard[:line_count] += unit.fetch(:line_count)
    end

    assigned_runnables = shards.flat_map { |shard| shard.fetch(:runnables) }
    expected_runnables = all_runnables(test_root: test_root)
    unless assigned_runnables.length == expected_runnables.length &&
           assigned_runnables.uniq.length == expected_runnables.length &&
           assigned_runnables.sort == expected_runnables
      abort 'Internal error: test sharding did not assign every runnable exactly once'
    end

    shards
  end

  def positive_integer(name)
    value = Integer(ENV.fetch(name, ''), exception: false)
    abort "#{name} must be a positive integer" unless value&.positive?

    value
  end

  def write_manifest(path, selected_runnables)
    return if path.to_s.empty?

    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#{selected_runnables.join("\n")}\n")
  end

  def source_file(runnable)
    runnable.sub(/:\d+\z/, '')
  end

  def required_services(selected_runnables)
    selected_files = selected_runnables.map { |runnable| source_file(runnable) }.uniq
    SERVICE_TEST_FILES.transform_values do |service_files|
      service_files.any? { |service_file| selected_files.include?(service_file) }
    end
  end

  def cache_writer_shards(shards)
    SERVICE_TEST_FILES.keys.each_with_object({}) do |service, writers|
      index = shards.index do |shard|
        required_services(shard.fetch(:runnables)).fetch(service)
      end
      writers[service] = index && (index + 1)
    end
  end

  def image_build_targets(shards:, logical_shards:, api_cache_writer:, cache_write_enabled: true)
    targets = [api_cache_writer ? 'api-cache-writer' : 'api']
    selected_runnables = logical_shards.flat_map do |shard_number|
      shards.fetch(shard_number - 1).fetch(:runnables)
    end
    required = required_services(selected_runnables)
    cache_writers = cache_writer_shards(shards)

    SERVICE_TEST_FILES.each_key do |service|
      next unless required.fetch(service)

      target = service.to_s
      if cache_write_enabled && logical_shards.include?(cache_writers.fetch(service))
        target += '-cache-writer'
      end
      targets << target
    end
    targets
  end

  def shard_plan_fingerprint(shards)
    contents = shards.each_with_index.map do |shard, index|
      "#{index + 1}\0#{shard.fetch(:runnables).sort.join("\0")}"
    end
    Digest::SHA256.hexdigest(contents.join("\n"))
  end

  def scheduling_weights(shards:, worker_count:, runtime_profile:)
    fallback = shards.map { |shard| shard.fetch(:weight) }
    return fallback unless runtime_profile.fetch(:shard_count, nil) == shards.length
    return fallback unless runtime_profile.fetch(:worker_count, nil) == worker_count
    return fallback unless runtime_profile.fetch(:fingerprint, nil) == shard_plan_fingerprint(shards)

    weights = runtime_profile.fetch(:weights, nil)
    unless weights.is_a?(Array) && weights.length == shards.length && weights.all?(&:positive?)
      abort 'The hosted shard runtime profile contains invalid weights'
    end
    weights
  end

  # Pack logical shards onto the smaller number of hosted runners available to
  # the repository. Each worker runs its assigned logical shards concurrently,
  # so balancing their combined measured weight avoids four waves of queued
  # GitHub jobs when the account has five runner slots.
  def worker_assignments(shards:, worker_count:, runtime_profile: HOSTED_SHARD_RUNTIME_PROFILE)
    abort 'TEST_SHARD_WORKER_COUNT must be a positive integer' unless worker_count.positive?
    if worker_count > shards.length
      abort "TEST_SHARD_WORKER_COUNT cannot exceed the #{shards.length} logical shards"
    end
    unless (shards.length % worker_count).zero?
      abort 'Logical shard count must be divisible by TEST_SHARD_WORKER_COUNT'
    end

    worker_weights = scheduling_weights(
      shards: shards,
      worker_count: worker_count,
      runtime_profile: runtime_profile
    )
    shards_per_worker = shards.length / worker_count
    workers = Array.new(worker_count) { { weight: 0.0, shard_numbers: [] } }
    weighted_shard_indices = shards.each_index.sort_by do |index|
      [-worker_weights.fetch(index), index]
    end
    weighted_shard_indices.each do |index|
      eligible_workers = workers.each_index.select do |worker_index|
        workers.fetch(worker_index).fetch(:shard_numbers).length < shards_per_worker
      end
      worker_index = eligible_workers.min_by do |candidate|
        [workers.fetch(candidate).fetch(:weight), candidate]
      end
      worker = workers.fetch(worker_index)
      worker.fetch(:shard_numbers) << (index + 1)
      worker[:weight] += worker_weights.fetch(index)
    end
    workers.each { |worker| worker.fetch(:shard_numbers).sort! }

    assigned = workers.flat_map { |worker| worker.fetch(:shard_numbers) }
    expected = (1..shards.length).to_a
    unless assigned.sort == expected && assigned.uniq.length == expected.length
      abort 'Internal error: worker packing did not assign every logical shard exactly once'
    end

    workers
  end

  def write_github_output(path, selected_runnables, cache_writer_services: {})
    return if path.to_s.empty?

    File.open(path, 'a') do |output|
      required_services(selected_runnables).each do |service, required|
        output.puts "needs_#{service}=#{required}"
        output.puts "writes_#{service}_cache=#{cache_writer_services.fetch(service, false)}"
      end
    end
  end

  # Rails resolves each filter when its suite runs. Some integration tests
  # change the process working directory, so relative paths for later suites
  # can silently resolve outside the repository and select no tests. Execute
  # absolute paths while keeping repository-relative paths in CI manifests.
  def execution_runnables(selected_runnables, repository_root:)
    selected_runnables.map do |runnable|
      relative_source = source_file(runnable)
      line_suffix = runnable.delete_prefix(relative_source)
      "#{File.expand_path(relative_source, repository_root)}#{line_suffix}"
    end
  end

  def run_test_command(runnables)
    run_count = nil
    executed_runnables = []
    status = nil
    Open3.popen2e('bundle', 'exec', 'rails', 'test', *runnables, '--verbose') do |_stdin, output, wait_thread|
      output.each do |line|
        print line
        summary_match = line.match(/([\d,]+) runs, [\d,]+ assertions/)
        run_count = Integer(summary_match[1].delete(',')) if summary_match
        runnable_match = line.match(/\A([A-Za-z0-9_:]+)#(test_.+?) =/)
        executed_runnables << "#{runnable_match[1]}##{runnable_match[2]}" if runnable_match
      end
      status = wait_thread.value
    end
    [status.success?, run_count, executed_runnables]
  end

  def write_run_count(path, run_count)
    return if path.to_s.empty?

    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#{run_count}\n")
  end

  def write_executed_runnables(path, executed_runnables)
    return if path.to_s.empty?

    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#{executed_runnables.sort.join("\n")}\n")
  end

  def run_tests(selected_runnables, repository_root:, run_count_path:, executed_runnables_path: nil)
    runnables = execution_runnables(selected_runnables, repository_root: repository_root)
    puts "Rails test invocation: #{runnables.join(' ')}"
    $stdout.flush
    successful, run_count, executed_runnables = run_test_command(runnables)
    if run_count.nil?
      warn 'Rails test invocation produced no Minitest run count'
      successful = false
      run_count = 0
    elsif executed_runnables.length != run_count
      warn "Rails test invocation reported #{run_count} tests, " \
           "but #{executed_runnables.length} runnable identifiers were captured"
      successful = false
    end
    write_run_count(run_count_path, run_count)
    write_executed_runnables(executed_runnables_path, executed_runnables)
    exit 1 unless successful
  end

  def run(argv)
    valid_arguments = ['--dry-run', '--list-runnables']
    unknown_arguments = argv - valid_arguments
    abort "Unknown argument(s): #{unknown_arguments.join(' ')}" unless unknown_arguments.empty?
    if argv.include?('--list-runnables') && argv.length > 1
      abort '--list-runnables cannot be combined with another argument'
    end

    repository_root = File.expand_path('..', __dir__)
    test_root = File.join(repository_root, 'test')
    if argv.include?('--list-runnables')
      puts all_runnables(test_root: test_root)
      return
    end

    shard_count = positive_integer('TEST_SHARD_COUNT')
    shard_number = positive_integer('TEST_SHARD_NUMBER')
    abort "TEST_SHARD_NUMBER must be between 1 and #{shard_count}" if shard_number > shard_count

    shards = build(test_root: test_root, shard_count: shard_count)
    selected_shard = shards.fetch(shard_number - 1)
    selected_runnables = selected_shard.fetch(:runnables).sort

    puts "Test shard #{shard_number}/#{shard_count}: " \
         "#{selected_runnables.length} of #{shards.sum { |shard| shard[:runnables].length }} runnables, " \
         "estimated weight #{selected_shard[:weight].round(1)}"
    selected_runnables.each { |runnable| puts "  #{runnable}" }
    write_manifest(ENV.fetch('TEST_SHARD_MANIFEST', nil), selected_runnables)
    cache_writers = cache_writer_shards(shards)
    cache_writer_services = cache_writers.transform_values { |writer| writer == shard_number }
    write_github_output(
      ENV.fetch('TEST_SHARD_GITHUB_OUTPUT', nil),
      selected_runnables,
      cache_writer_services: cache_writer_services
    )

    return if argv.include?('--dry-run')

    $stdout.flush
    Dir.chdir(repository_root) do
      inventory_path = ENV.fetch('TEST_RUNNABLE_INVENTORY', nil)
      if shard_number == 1 && !inventory_path.to_s.empty?
        inventory_successful = system('bundle', 'exec', 'ruby', 'script/test_inventory.rb', inventory_path)
        exit 1 unless inventory_successful
      end
      run_tests(
        selected_runnables,
        repository_root: repository_root,
        run_count_path: ENV.fetch('TEST_SHARD_RUN_COUNT', nil),
        executed_runnables_path: ENV.fetch('TEST_SHARD_EXECUTED_RUNNABLES', nil)
      )
    end
  end
end

TestShard.run(ARGV) if $PROGRAM_NAME == __FILE__
