#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
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
    'test/models/task_test.rb' => 160.0,
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

  def split_units(path, relative_path, part_count)
    methods = method_runnables(path, relative_path)
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

  def runnable_units(test_root:)
    test_files = Dir.glob(File.join(test_root, '**', '*_test.rb'))
    abort "No test files found under #{test_root}" if test_files.empty?

    test_files.flat_map do |path|
      relative_path = repository_relative(path, test_root)
      part_count = SPLIT_TEST_FILES[relative_path]
      next split_units(path, relative_path, part_count) if part_count

      line_count = File.foreach(path).count
      [{
        weight: file_weight(relative_path, line_count),
        line_count: line_count,
        runnables: [relative_path]
      }]
    end
  end

  def all_runnables(test_root:)
    runnable_units(test_root: test_root).flat_map { |unit| unit.fetch(:runnables) }.sort
  end

  def build(test_root:, shard_count:)
    units = runnable_units(test_root: test_root)
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
