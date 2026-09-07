# frozen_string_literal: true

require 'test_helper'

class UnitSimilarityCleanupTest < ActiveSupport::TestCase
  def test_jplag_cleanup_preserves_another_units_workspace
    unit = FactoryBot.create(:unit, with_students: false, task_count: 0)
    current_root = Rails.root.join('tmp', 'jplag', "unit-#{unit.id}")
    tasks_dir = current_root.join('task-definition')
    other_root = Rails.root.join('tmp', 'jplag', "other-unit-#{SecureRandom.hex(6)}")
    sentinel = other_root.join('in-progress.sentinel')

    FileUtils.mkdir_p(tasks_dir)
    FileUtils.mkdir_p(other_root)
    FileUtils.touch(sentinel)

    unit.stub(:system, true) do
      unit.send(
        :run_jplag_on_done_files,
        jplag_task_definition,
        tasks_dir,
        [],
        Rails.root.join('tmp/jplag-results/report.jplag').to_s
      )
    end

    assert_not Dir.exist?(tasks_dir), 'the completed task workspace should be removed'
    assert File.exist?(sentinel), "another unit's in-progress workspace must survive cleanup"
  ensure
    FileUtils.rm_rf(current_root) if current_root
    FileUtils.rm_rf(other_root) if other_root
  end

  def test_jplag_cleanup_runs_when_the_container_command_fails
    unit = FactoryBot.create(:unit, with_students: false, task_count: 0)
    current_root = Rails.root.join('tmp', 'jplag', "unit-#{unit.id}")
    tasks_dir = current_root.join('task-definition')
    other_root = Rails.root.join('tmp', 'jplag', "other-unit-#{SecureRandom.hex(6)}")
    sentinel = other_root.join('in-progress.sentinel')

    FileUtils.mkdir_p(tasks_dir)
    FileUtils.mkdir_p(other_root)
    FileUtils.touch(sentinel)

    system_calls = 0
    run_command = lambda do |*_command|
      system_calls += 1
      system_calls < 3
    end

    error = assert_raises(RuntimeError) do
      unit.stub(:system, run_command) do
        unit.send(
          :run_jplag_on_done_files,
          jplag_task_definition,
          tasks_dir,
          [],
          Rails.root.join('tmp/jplag-results/report.jplag').to_s
        )
      end
    end

    assert_equal 'Failed to run JPlag similarity check', error.message
    assert_not Dir.exist?(tasks_dir), 'the failed task workspace should be removed'
    assert File.exist?(sentinel), "another unit's in-progress workspace must survive failed cleanup"
  ensure
    FileUtils.rm_rf(current_root) if current_root
    FileUtils.rm_rf(other_root) if other_root
  end

  def test_jplag_unit_root_cleanup_runs_after_a_top_level_failure
    unit = FactoryBot.create(:unit, with_students: false, task_count: 0)
    current_root = Rails.root.join('tmp', 'jplag', "unit-#{unit.id}")
    other_root = Rails.root.join('tmp', 'jplag', "other-unit-#{SecureRandom.hex(6)}")
    sentinel = other_root.join('in-progress.sentinel')

    FileUtils.mkdir_p(current_root)
    FileUtils.mkdir_p(other_root)
    FileUtils.touch(sentinel)

    failing_definitions = Object.new
    failing_definitions.define_singleton_method(:each) { raise 'simulated scan setup failure' }

    error = assert_raises(RuntimeError) do
      unit.stub(:task_definitions, failing_definitions) do
        unit.check_jplag_similarity(force: true)
      end
    end

    assert_equal 'simulated scan setup failure', error.message
    assert_not Dir.exist?(current_root), 'the failed unit workspace should be removed'
    assert File.exist?(sentinel), "another unit's in-progress workspace must survive unit cleanup"
  ensure
    FileUtils.rm_rf(current_root) if current_root
    FileUtils.rm_rf(other_root) if other_root
  end

  def test_hostile_unit_code_cannot_escape_workspace_or_reach_a_shell
    unit = FactoryBot.create(:unit, with_students: false, task_count: 0)
    token = SecureRandom.hex(6)
    shell_marker = Rails.root.join("jplag-shell-marker-#{token}")
    hostile_code = "../escaped-#{token};touch #{shell_marker.basename};#"
    unit.update!(code: hostile_code)

    task_definition = hostile_jplag_task_definition(unit.id + 9_000_000)
    current_root = Rails.root.join('tmp', 'jplag', "unit-#{unit.id}")
    expected_tasks_dir = current_root.join(task_definition.id.to_s)
    legacy_escape_root = Rails.root.join('tmp', 'jplag', "#{hostile_code}-#{unit.id}")
    other_root = Rails.root.join('tmp', 'jplag', "unit-#{unit.id + 8_000_000}")
    sentinel = other_root.join('in-progress.sentinel')
    extracted_to = []
    docker_calls = []
    tasks = hostile_tasks(extracted_to)

    FileUtils.mkdir_p(other_root)
    FileUtils.touch(sentinel)

    capture_system = lambda do |*argv|
      docker_calls << argv
      true
    end

    unit.stub(:task_definitions, [task_definition]) do
      unit.stub(:tasks_for_definition, tasks) do
        unit.stub(:process_jplag_plagiarism_report, true) do
          unit.stub(:system, capture_system) do
            unit.check_jplag_similarity(force: true)
          end
        end
      end
    end

    assert_equal [expected_tasks_dir, expected_tasks_dir], extracted_to
    assert_equal 3, docker_calls.length
    assert docker_calls.all? { |argv| argv.length > 1 }, 'derived paths must never be passed through a command string'
    assert(docker_calls.all? { |argv| argv.first == 'docker' })
    assert_includes docker_calls.last, "/tmp/jplag/unit-#{unit.id}/#{task_definition.id}/submissions"
    assert_not File.exist?(shell_marker), 'unit code shell metacharacters must never execute'
    assert_not Dir.exist?(legacy_escape_root), 'unit code path traversal must not create a workspace'
    assert_not Dir.exist?(current_root), 'the hostile-code unit workspace should be cleaned'
    assert File.exist?(sentinel), "another unit's workspace must survive hostile-code cleanup"
  ensure
    FileUtils.rm_rf(current_root) if current_root
    FileUtils.rm_rf(legacy_escape_root) if legacy_escape_root
    FileUtils.rm_rf(other_root) if other_root
    FileUtils.rm_f(shell_marker) if shell_marker
  end

  private

  def jplag_task_definition
    task_definition = Struct.new(:plagiarism_warn_pct, :upload_requirements, :similarity_language)
                            .new(50, [], 'java')
    task_definition.define_singleton_method(:has_task_resources?) { false }
    task_definition
  end

  def hostile_jplag_task_definition(id)
    task_definition = Struct.new(
      :id,
      :similarity_language,
      :upload_requirements,
      :updated_at,
      :name,
      :plagiarism_warn_pct,
      :group_set,
      :abbreviation
    ).new(
      id,
      'java',
      [{ 'type' => 'code', 'tii_check' => true, 'name' => 'source' }],
      Time.zone.now,
      'Hostile code task',
      50,
      nil,
      'HOSTILE'
    )
    task_definition.define_singleton_method(:has_task_resources?) { false }
    task_definition.define_singleton_method(:glob_for_upload_requirement) { |_index| '*' }
    task_definition
  end

  def hostile_tasks(extracted_to)
    task_list = Array.new(2) do
      task = Object.new
      task.define_singleton_method(:has_pdf) { true }
      task.define_singleton_method(:extract_file_from_done) do |to_path, _pattern, _destination|
        extracted_to << Pathname(to_path)
      end
      task
    end

    tasks = Object.new
    tasks.define_singleton_method(:select) { |&block| task_list.select(&block) }
    tasks.define_singleton_method(:where) { |_query, _time| tasks }
    tasks
  end
end
