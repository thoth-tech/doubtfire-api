# frozen_string_literal: true

require 'test_helper'
require 'time'

class PeerProgressApiTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper

  RESPONSE_KEYS = %w[
    task_definition_id
    unit_id
    target_grade
    submitted_percentage
    completed_percentage
    status_distribution
    distribution_available
    distribution_unavailable_reason
    is_suppressed
    is_stale
    is_feature_enabled
    is_user_enabled
    last_updated_at
    unavailable_reason
    unavailable_message
  ].freeze

  FORBIDDEN_KEYS = %w[
    cohort_size
    submitted_count
    status_counts
    count
    user_id
    student_id
    username
    first_name
    last_name
    project_id
    task_status
    marks
    feedback
  ].freeze

  setup do
    clear_auth_header

    @original_minimum_cohort_size =
      ENV.fetch('DF_PPI_MINIMUM_COHORT_SIZE', nil)

    @original_stale_after_hours =
      ENV.fetch('DF_PPI_STALE_AFTER_HOURS', nil)
    ENV['DF_PPI_MINIMUM_COHORT_SIZE'] =
      PeerProgressApi::MINIMUM_SAFE_COHORT_SIZE.to_s
    ENV['DF_PPI_STALE_AFTER_HOURS'] = '48'

    @unit = create(
      :unit,
      with_students: false,
      task_count: 0,
      stream_count: 0,
      tutorials: 1,
      staff_count: 0,
      outcome_count: 0
    )
    @unit.update!(peer_progress_enabled: true)

    @student = create(:user, :student)
    @project = @unit.enrol_student(
      @student,
      @unit.tutorials.first.campus
    )
    @project.update!(target_grade: 1)
    @project.update!(target_grade_changed_at: 1.year.ago)

    @task_definition = create(
      :task_definition,
      unit: @unit,
      target_grade: 0,
      start_date: Time.zone.parse('2026-01-01 00:00:00 UTC'),
      outcome_count: 0
    )
  end

  teardown do
    restore_env(
      'DF_PPI_MINIMUM_COHORT_SIZE',
      @original_minimum_cohort_size
    )
    restore_env(
      'DF_PPI_STALE_AFTER_HOURS',
      @original_stale_after_hours
    )
    clear_auth_header
  end

  test 'requires authentication' do
    get endpoint

    assert_equal 419, last_response.status
    assert_private_no_store
  end

  test 'returns a privacy-safe normal response for the owning student' do
    create_snapshot(
      submitted_percentage: 60,
      cohort_size: 25,
      status_counts: safe_status_counts
    )

    request_as(@student)

    assert_equal 200, last_response.status, last_response.body
    body = last_response_body
    assert_peer_progress_response_contract(body)

    assert_equal @task_definition.id, body['task_definition_id']
    assert_equal @unit.id, body['unit_id']
    assert_equal @project.target_grade, body['target_grade']
    assert_equal 60.0, body['submitted_percentage']
    assert_equal 10.0, body['completed_percentage']
    assert_equal true, body['distribution_available']
    assert_nil body['distribution_unavailable_reason']
    assert_equal PeerProgressDistributionPolicy::STATUS_KEYS,
                 body['status_distribution'].pluck('status')
    assert_equal false, body['is_suppressed']
    assert_equal false, body['is_stale']
    assert_equal true, body['is_feature_enabled']
    assert_equal true, body['is_user_enabled']
    assert body['last_updated_at'].present?
    assert_nil body['unavailable_reason']
    assert_equal '', body['unavailable_message']
  end

  test 'excludes a submitted complete viewer before compact and detailed output' do
    viewer_task = create(
      :task,
      project: @project,
      task_definition: @task_definition,
      task_status: TaskStatus.complete,
      file_uploaded_at: 2.hours.ago,
      submission_date: 2.hours.ago
    )
    calculated_at = viewer_task.updated_at + 1.minute
    create(
      :peer_progress_snapshot,
      unit: @unit,
      task_definition: @task_definition,
      target_grade: @project.target_grade,
      cohort_size: 22,
      submitted_count: 1,
      submitted_percentage: 4.55,
      status_counts: empty_status_counts.merge(
        'not_started' => 21,
        'complete' => 1
      ),
      calculated_at: calculated_at
    )

    request_as(@student)

    body = last_response_body
    assert_equal 200, last_response.status
    assert_equal 0.0, body['submitted_percentage']
    assert_equal 0.0, body['completed_percentage']
    assert_equal true, body['distribution_available']
    assert_equal 100.0,
                 distribution_percentage(body, 'not_started')
    assert_equal 0.0,
                 distribution_percentage(body, 'complete')
  end

  test 'excludes an unsubmitted viewer from a fully complete peer cohort' do
    create(
      :peer_progress_snapshot,
      unit: @unit,
      task_definition: @task_definition,
      target_grade: @project.target_grade,
      cohort_size: 22,
      submitted_count: 21,
      submitted_percentage: 95.45,
      status_counts: empty_status_counts.merge(
        'not_started' => 1,
        'complete' => 21
      ),
      calculated_at: Time.zone.now
    )

    request_as(@student)

    body = last_response_body
    assert_equal 200, last_response.status
    assert_equal 100.0, body['submitted_percentage']
    assert_equal 100.0, body['completed_percentage']
    assert_equal true, body['distribution_available']
    assert_equal 0.0,
                 distribution_percentage(body, 'not_started')
    assert_equal 100.0,
                 distribution_percentage(body, 'complete')
  end

  test 'requires twenty one remaining peers rather than counting the viewer' do
    create_snapshot(
      submitted_percentage: 50,
      cohort_size: 20
    )

    request_as(@student)

    assert_equal 200, last_response.status
    assert_equal true, last_response_body['is_suppressed']
    assert_nil last_response_body['submitted_percentage']
  end

  test 'fails closed when the viewer task changed after aggregation' do
    calculated_at = 1.hour.ago
    create_snapshot(
      submitted_percentage: 50,
      cohort_size: PeerProgressApi::MINIMUM_SAFE_COHORT_SIZE,
      calculated_at: calculated_at
    )
    create(
      :task,
      project: @project,
      task_definition: @task_definition,
      task_status: TaskStatus.complete,
      updated_at: calculated_at + 1.minute
    )

    request_as(@student)

    body = last_response_body
    assert_equal 200, last_response.status
    assert_nil body['submitted_percentage']
    assert_nil body['completed_percentage']
    assert_nil body['status_distribution']
    assert_equal 'snapshot_unavailable', body['unavailable_reason']
  end

  test 'fails closed when the viewer re-enrolled after aggregation' do
    calculated_at = 1.hour.ago
    create_snapshot(
      submitted_percentage: 50,
      cohort_size: PeerProgressApi::MINIMUM_SAFE_COHORT_SIZE,
      calculated_at: calculated_at
    )
    @project.update!(enrolled: false)
    @project.update!(enrolled: true)

    request_as(@student)

    body = last_response_body
    assert_equal 200, last_response.status
    assert_nil body['submitted_percentage']
    assert_nil body['completed_percentage']
    assert_equal 'snapshot_unavailable', body['unavailable_reason']
  end

  test 'fails closed when a legacy snapshot has no exact submitted count' do
    create_snapshot(
      submitted_percentage: 50,
      cohort_size: PeerProgressApi::MINIMUM_SAFE_COHORT_SIZE,
      submitted_count: nil
    )

    request_as(@student)

    body = last_response_body
    assert_equal 200, last_response.status
    assert_nil body['submitted_percentage']
    assert_nil body['completed_percentage']
    assert_nil body['status_distribution']
    assert_equal 'aggregation_incomplete', body['unavailable_reason']
  end

  test 'suppresses a detailed vector that jointly reveals exact counts' do
    status_counts = empty_status_counts.merge(
      'not_started' => 6,
      'complete' => 18
    )
    create_snapshot(
      submitted_percentage: 75,
      cohort_size: 24,
      status_counts: status_counts
    )

    request_as(@student)

    body = last_response_body
    assert_equal 200, last_response.status
    assert_equal 80.0, body['submitted_percentage']
    assert_equal 80.0, body['completed_percentage']
    assert_nil body['status_distribution']
    assert_equal false, body['distribution_available']
    assert_equal 'privacy_protection',
                 body['distribution_unavailable_reason']
    assert_nil body['unavailable_reason']
  end

  test 'honours a students disabled peer progress preference' do
    @student.update!(display_peer_progress: false)
    create_snapshot(
      submitted_percentage: 60,
      cohort_size: 25,
      status_counts: safe_status_counts
    )

    request_as(@student)

    body = last_response_body
    assert_equal 200, last_response.status
    assert_nil body['submitted_percentage']
    assert_nil body['completed_percentage']
    assert_nil body['status_distribution']
    assert_equal false, body['distribution_available']
    assert_equal false, body['is_user_enabled']
    assert_equal 'user_disabled', body['unavailable_reason']
    assert_equal 'user_disabled',
                 body['distribution_unavailable_reason']
  end

  test 'returns a genuine zero as zero rather than unavailable' do
    create_snapshot(
      submitted_percentage: 0,
      cohort_size: PeerProgressApi::MINIMUM_SAFE_COHORT_SIZE
    )

    request_as(@student)

    assert_equal 200, last_response.status
    body = last_response_body
    assert_peer_progress_response_contract(body)

    assert_equal 0.0, body['submitted_percentage']
    assert_equal false, body['is_suppressed']
    assert_equal false, body['is_stale']
    assert_equal '', body['unavailable_message']
  end

  test 'does not allow access before a student specific flexible start date' do
    @unit.update!(allow_flexible_dates: true)

    create(
      :task,
      project: @project,
      task_definition: @task_definition,
      task_status: TaskStatus.not_started,
      target_start_date: 1.day.from_now
    )

    request_as(@student)

    assert_peer_progress_not_found
  end

  test 'does not allow access before a target grade specific start date' do
    @unit.update!(allow_flexible_dates: true)

    TaskDefinitionGradeDueDate.create!(
      task_definition: @task_definition,
      target_grade: @project.target_grade,
      start_date: 1.day.from_now,
      target_due_date: @task_definition.target_date
    )

    request_as(@student)

    assert_peer_progress_not_found
  end

  test 'allows access after the target grade specific start date' do
    @unit.update!(allow_flexible_dates: true)

    TaskDefinitionGradeDueDate.create!(
      task_definition: @task_definition,
      target_grade: @project.target_grade,
      start_date: 1.day.ago,
      target_due_date: @task_definition.target_date
    )

    create_snapshot(
      submitted_percentage: 50,
      cohort_size: PeerProgressApi::MINIMUM_SAFE_COHORT_SIZE
    )

    request_as(@student)

    assert_equal 200, last_response.status
    assert_equal 50.0, last_response_body['submitted_percentage']
  end

  test 'does not create a task row while checking the release date' do
    create_snapshot(
      submitted_percentage: 50,
      cohort_size: PeerProgressApi::MINIMUM_SAFE_COHORT_SIZE
    )

    assert_no_difference('Task.count') do
      request_as(@student)
    end

    assert_equal 200, last_response.status
  end

  test 'quantises the student percentage to ten point buckets' do
    create_snapshot(
      submitted_percentage: 61,
      cohort_size: PeerProgressApi::MINIMUM_SAFE_COHORT_SIZE
    )

    request_as(@student)

    assert_equal 200, last_response.status
    assert_equal 60.0, last_response_body['submitted_percentage']
  end

  test 'fails closed when the cohort configuration is below the privacy floor' do
    create_snapshot(
      submitted_percentage: 50,
      cohort_size: PeerProgressApi::MINIMUM_SAFE_COHORT_SIZE
    )

    ENV['DF_PPI_MINIMUM_COHORT_SIZE'] = '20'

    request_as(@student)

    assert_equal 503, last_response.status
    assert_equal(
      PeerProgressApi::CONFIG_ERROR_MESSAGE,
      last_response_body['error']
    )
    assert_private_no_store
  end

  test 'accepts a configured threshold above the privacy floor' do
    configured_threshold = PeerProgressApi::MINIMUM_SAFE_COHORT_SIZE + 1
    ENV['DF_PPI_MINIMUM_COHORT_SIZE'] = configured_threshold.to_s

    create_snapshot(
      submitted_percentage: 50,
      cohort_size: configured_threshold
    )

    request_as(@student)

    assert_equal 200, last_response.status
    assert_equal 50.0, last_response_body['submitted_percentage']
    assert_equal false, last_response_body['is_suppressed']
  end

  test 'does not allow a student to read another students project' do
    other_student = create(:user, :student)
    other_project = @unit.enrol_student(
      other_student,
      @unit.tutorials.first.campus
    )
    other_project.update!(target_grade: 1)

    request_as(
      @student,
      endpoint(project: other_project)
    )

    assert_peer_progress_not_found
  end

  test 'does not allow a tutor to use the student endpoint' do
    tutor = create(:user, :tutor)
    @unit.employ_staff(tutor, Role.tutor)

    request_as(tutor)

    assert_peer_progress_not_found
  end

  test 'does not allow an unenrolled project' do
    @project.update!(enrolled: false)

    request_as(@student)

    assert_peer_progress_not_found
  end

  test 'does not allow an inactive unit in the first release' do
    @unit.update!(active: false)

    request_as(@student)

    assert_peer_progress_not_found
  end

  test 'does not allow a task from another unit' do
    other_unit = create(
      :unit,
      with_students: false,
      task_count: 0,
      stream_count: 0,
      tutorials: 0,
      staff_count: 0,
      outcome_count: 0
    )
    other_task = create(
      :task_definition,
      unit: other_unit,
      target_grade: 0,
      start_date: 1.day.ago,
      outcome_count: 0
    )

    request_as(
      @student,
      endpoint(task_definition: other_task)
    )

    assert_peer_progress_not_found
  end

  test 'does not allow a task above the students target grade' do
    higher_grade_task = create(
      :task_definition,
      unit: @unit,
      target_grade: 2,
      start_date: 1.day.ago,
      outcome_count: 0
    )

    request_as(
      @student,
      endpoint(task_definition: higher_grade_task)
    )

    assert_peer_progress_not_found
  end

  test 'does not allow an unreleased task' do
    future_task = create(
      :task_definition,
      unit: @unit,
      target_grade: 0,
      start_date: 1.day.from_now,
      outcome_count: 0
    )

    request_as(
      @student,
      endpoint(task_definition: future_task)
    )

    assert_peer_progress_not_found
  end

  test 'returns a neutral unavailable state when no snapshot exists' do
    request_as(@student)

    assert_equal 200, last_response.status
    body = last_response_body
    assert_peer_progress_response_contract(body)

    assert_nil body['submitted_percentage']
    assert_equal false, body['is_suppressed']
    assert_equal false, body['is_stale']
    assert_equal true, body['is_feature_enabled']
    assert_nil body['last_updated_at']
    assert body['unavailable_message'].present?
  end

  test 'suppresses the formerly unsafe cohort of twenty' do
    create_snapshot(
      submitted_percentage: 50,
      cohort_size: 20
    )

    request_as(@student)

    assert_equal 200, last_response.status
    body = last_response_body
    assert_peer_progress_response_contract(body)

    assert_nil body['submitted_percentage']
    assert_equal true, body['is_suppressed']
    assert_equal false, body['is_stale']
    assert body['unavailable_message'].present?
    assert_not body.key?('cohort_size')
  end

  test 'shows a cohort at the exact configured threshold' do
    create_snapshot(
      submitted_percentage: 40,
      cohort_size: PeerProgressApi::MINIMUM_SAFE_COHORT_SIZE
    )

    request_as(@student)

    assert_equal 200, last_response.status
    body = last_response_body
    assert_peer_progress_response_contract(body)

    assert_equal 40.0, body['submitted_percentage']
    assert_equal false, body['is_suppressed']
  end

  test 'keeps half a bucket wider than one students share of the smallest cohort' do
    # The zero and hundred edge buckets are only non-singletons while one
    # student's share is smaller than half the bucket width.
    assert_operator(
      PeerProgressApi::PERCENTAGE_BUCKET_SIZE / 2.0,
      :>,
      100.0 / PeerProgressApi::MINIMUM_SAFE_COHORT_SIZE,
      'Half of PERCENTAGE_BUCKET_SIZE must exceed one student share, or an ' \
      'edge bucket reveals the exact submitted count'
    )
  end

  test 'does not let the quantised percentage reveal the submitted count' do
    minimum = PeerProgressApi::MINIMUM_SAFE_COHORT_SIZE

    (minimum..1_000).each do |cohort_size|
      singleton_buckets = quantised_count_groups(cohort_size).select do |_bucket, counts|
        counts.one?
      end

      assert_empty(
        singleton_buckets,
        "cohort #{cohort_size} exposes exact submitted counts"
      )
    end

    floor_groups = quantised_count_groups(minimum)
    assert_equal [0, 1], floor_groups.fetch(0.0)
    assert_equal [minimum - 1, minimum], floor_groups.fetch(100.0)
  end

  test 'hides the percentage when an active unit snapshot is stale' do
    create_snapshot(
      submitted_percentage: 50,
      cohort_size: PeerProgressApi::MINIMUM_SAFE_COHORT_SIZE,
      calculated_at: 49.hours.ago
    )

    request_as(@student)

    assert_equal 200, last_response.status
    body = last_response_body
    assert_peer_progress_response_contract(body)

    assert_nil body['submitted_percentage']
    assert_equal false, body['is_suppressed']
    assert_equal true, body['is_stale']
    assert body['last_updated_at'].present?
    assert body['unavailable_message'].present?
  end

  test 'returns a disabled state when the unit has disabled PPI' do
    @unit.update!(peer_progress_enabled: false)

    request_as(@student)

    assert_equal 200, last_response.status
    body = last_response_body
    assert_peer_progress_response_contract(body)

    assert_nil body['submitted_percentage']
    assert_equal false, body['is_suppressed']
    assert_equal false, body['is_stale']
    assert_equal false, body['is_feature_enabled']
    assert_nil body['last_updated_at']
    assert body['unavailable_message'].present?
  end

  test 'ignores a browser supplied target grade' do
    create_snapshot(
      submitted_percentage: 60,
      cohort_size: PeerProgressApi::MINIMUM_SAFE_COHORT_SIZE
    )

    request_as(
      @student,
      "#{endpoint}?target_grade=3"
    )

    assert_equal 200, last_response.status
    body = last_response_body
    assert_peer_progress_response_contract(body)

    assert_equal @project.target_grade, body['target_grade']
    assert_equal 60.0, body['submitted_percentage']
  end

  test 'returns a neutral unavailable state when no target grade is selected' do
    # Intentionally bypass validations and callbacks to verify that the API
    # safely handles a project with no stored target grade.
    # rubocop:disable Rails/SkipsModelValidations
    @project.update_column(:target_grade, nil)
    # rubocop:enable Rails/SkipsModelValidations

    request_as(@student)

    assert_equal 200, last_response.status
    body = last_response_body
    assert_peer_progress_response_contract(body)

    assert_nil body['target_grade']
    assert_nil body['submitted_percentage']
    assert_equal false, body['is_suppressed']
    assert_equal false, body['is_stale']
    assert_equal true, body['is_feature_enabled']
    assert_nil body['last_updated_at']
    assert_equal(
      PeerProgressApi::UNAVAILABLE_MESSAGE,
      body['unavailable_message']
    )
  end

  test 'does not expose an invalid stored target grade' do
    # Intentionally bypass validations and callbacks to verify that the API
    # safely handles an invalid legacy target-grade value.
    # rubocop:disable Rails/SkipsModelValidations
    @project.update_column(:target_grade, 999)
    # rubocop:enable Rails/SkipsModelValidations

    request_as(@student)

    assert_equal 200, last_response.status

    body = last_response_body
    assert_peer_progress_response_contract(body)

    assert_nil body['target_grade']
    assert_nil body['submitted_percentage']
    assert_equal false, body['is_suppressed']
    assert_equal false, body['is_stale']
    assert_equal true, body['is_feature_enabled']
    assert_nil body['last_updated_at']
    assert_equal(
      PeerProgressApi::UNAVAILABLE_MESSAGE,
      body['unavailable_message']
    )
  end

  test 'returns unavailable rather than zero for an empty stored cohort' do
    create_snapshot(
      submitted_percentage: nil,
      cohort_size: 0
    )

    request_as(@student)

    assert_equal 200, last_response.status

    body = last_response_body
    assert_peer_progress_response_contract(body)

    assert_nil body['submitted_percentage']
    assert_equal true, body['is_suppressed']
    assert_equal false, body['is_stale']
    assert_equal true, body['is_feature_enabled']
    assert body['last_updated_at'].present?
    assert body['unavailable_message'].present?
  end

  test 'returns the snapshot timestamp in UTC ISO 8601 format' do
    calculated_at = Time.zone.parse('2026-08-10 03:15:00 UTC')

    create_snapshot(
      submitted_percentage: 62.5,
      cohort_size: PeerProgressApi::MINIMUM_SAFE_COHORT_SIZE,
      calculated_at: calculated_at
    )

    request_as(@student)

    assert_equal 200, last_response.status

    body = last_response_body
    assert_peer_progress_response_contract(body)

    assert_equal(
      calculated_at.utc.iso8601,
      body['last_updated_at']
    )
  end

  test 'fails closed when the stale window configuration is missing' do
    create_snapshot(
      submitted_percentage: 50,
      cohort_size: PeerProgressApi::MINIMUM_SAFE_COHORT_SIZE
    )

    ENV.delete('DF_PPI_STALE_AFTER_HOURS')

    request_as(@student)

    assert_equal 503, last_response.status
    assert_equal(
      PeerProgressApi::CONFIG_ERROR_MESSAGE,
      last_response_body['error']
    )
    assert_private_no_store
  end

  test 'returns the same generic response for unknown project and task ids' do
    unknown_project_id = Project.maximum(:id).to_i + 10_000

    request_as(
      @student,
      "/api/projects/#{unknown_project_id}/task_def_id/" \
      "#{@task_definition.id}/peer_progress"
    )

    assert_peer_progress_not_found

    unknown_task_id = TaskDefinition.maximum(:id).to_i + 10_000

    request_as(
      @student,
      "/api/projects/#{@project.id}/task_def_id/" \
      "#{unknown_task_id}/peer_progress"
    )

    assert_peer_progress_not_found
  end

  test 'fails closed for invalid positive integer configuration' do
    create_snapshot(
      submitted_percentage: 50,
      cohort_size: PeerProgressApi::MINIMUM_SAFE_COHORT_SIZE
    )

    [
      ['DF_PPI_MINIMUM_COHORT_SIZE', '0'],
      ['DF_PPI_MINIMUM_COHORT_SIZE', 'not-a-number'],
      ['DF_PPI_STALE_AFTER_HOURS', '-1'],
      ['DF_PPI_STALE_AFTER_HOURS', '1.5']
    ].each do |name, value|
      original = ENV.fetch(name, nil)

      begin
        ENV[name] = value
        request_as(@student)

        assert_equal 503, last_response.status
        assert_equal(
          PeerProgressApi::CONFIG_ERROR_MESSAGE,
          last_response_body['error']
        )
        assert_private_no_store
      ensure
        restore_env(name, original)
      end
    end
  end

  test 'keeps a snapshot available at the exact stale boundary' do
    travel_to Time.zone.parse('2026-08-10 12:00:00 UTC') do
      create_snapshot(
        submitted_percentage: 50,
        cohort_size: PeerProgressApi::MINIMUM_SAFE_COHORT_SIZE,
        calculated_at: 48.hours.ago
      )

      request_as(@student)

      assert_equal 200, last_response.status

      body = last_response_body
      assert_peer_progress_response_contract(body)

      assert_equal 50.0, body['submitted_percentage']
      assert_equal false, body['is_stale']
    end
  end

  test 'does not serve a snapshot created before the target grade changed' do
    travel_to Time.zone.parse('2026-08-10 12:00:00 UTC') do
      create_snapshot(
        target_grade: 2,
        submitted_percentage: 60,
        cohort_size: PeerProgressApi::MINIMUM_SAFE_COHORT_SIZE,
        calculated_at: 1.hour.ago
      )

      @project.update!(target_grade: 2)

      request_as(@student)

      assert_equal 200, last_response.status

      body = last_response_body
      assert_peer_progress_response_contract(body)

      assert_equal 2, body['target_grade']
      assert_nil body['submitted_percentage']
      assert_equal false, body['is_suppressed']
      assert_nil body['last_updated_at']
      assert body['unavailable_message'].present?
    end
  end

  test 'records when a project target grade changes' do
    project = create(:project)
    original_timestamp = project.target_grade_changed_at

    travel 1.minute
    project.update!(target_grade: project.target_grade + 1)

    assert_operator(
      project.reload.target_grade_changed_at,
      :>,
      original_timestamp
    )
  end

  test 'does not change the grade timestamp for an unrelated update' do
    project = create(:project)
    original_timestamp = project.target_grade_changed_at

    travel 1.minute
    project.update!(started: !project.started)

    assert_equal(
      original_timestamp,
      project.reload.target_grade_changed_at
    )
  end

  test 'fails closed when required PPI configuration is missing' do
    create_snapshot(
      submitted_percentage: 50,
      cohort_size: PeerProgressApi::MINIMUM_SAFE_COHORT_SIZE
    )
    ENV.delete('DF_PPI_MINIMUM_COHORT_SIZE')

    request_as(@student)

    assert_equal 503, last_response.status
    assert_equal(
      PeerProgressApi::CONFIG_ERROR_MESSAGE,
      last_response_body['error']
    )
    assert_private_no_store
  end

  test 'serves a fresh snapshot calculated after the target grade changed' do
    travel_to Time.zone.parse('2026-08-10 12:00:00 UTC') do
      @project.update!(target_grade: 2)

      travel 1.minute

      create_snapshot(
        target_grade: 2,
        submitted_percentage: 61,
        cohort_size: PeerProgressApi::MINIMUM_SAFE_COHORT_SIZE,
        calculated_at: Time.zone.now
      )

      request_as(@student)

      assert_equal 200, last_response.status
      assert_equal 60.0, last_response_body['submitted_percentage']
    end
  end

  private

  def endpoint(project: @project, task_definition: @task_definition)
    "/api/projects/#{project.id}/task_def_id/" \
      "#{task_definition.id}/peer_progress"
  end

  def request_as(user, path = endpoint)
    clear_auth_header
    add_auth_header_for(user: user)
    get path
  end

  def create_snapshot(
    submitted_percentage:,
    cohort_size:,
    calculated_at: Time.zone.now,
    target_grade: @project.target_grade,
    status_counts: :default,
    submitted_count: :default
  )
    @project.update!(updated_at: calculated_at - 1.second) if
      @project.updated_at > calculated_at

    peer_status_counts = if status_counts == :default
                           empty_status_counts.merge(
                             'not_started' => cohort_size
                           )
                         else
                           status_counts
                         end
    stored_status_counts = peer_status_counts&.dup
    if stored_status_counts
      stored_status_counts['not_started'] += 1
    end

    peer_submitted_count = if submitted_count == :default
                             if submitted_percentage.nil?
                               nil
                             else
                               ((submitted_percentage * cohort_size) / 100.0).round
                             end
                           else
                             submitted_count
                           end
    stored_submitted_count = peer_submitted_count
    stored_percentage = submitted_percentage
    unless stored_submitted_count.nil?
      stored_percentage = ((stored_submitted_count * 100.0) /
                           (cohort_size + 1)).round(2)
    end

    create(
      :peer_progress_snapshot,
      unit: @unit,
      task_definition: @task_definition,
      target_grade: target_grade,
      submitted_percentage: stored_percentage,
      submitted_count: stored_submitted_count,
      cohort_size: cohort_size + 1,
      status_counts: stored_status_counts,
      calculated_at: calculated_at
    )
  end

  def empty_status_counts
    PeerProgressDistributionPolicy::STATUS_KEYS.index_with { 0 }
  end

  def safe_status_counts
    empty_status_counts.merge(
      'not_started' => 5,
      'working_on_it' => 5,
      'ready_for_feedback' => 4,
      'fix_and_resubmit' => 3,
      'redo' => 3,
      'complete' => 3,
      'fail' => 2
    )
  end

  def quantised_count_groups(cohort_size)
    bucket_size = PeerProgressApi::PERCENTAGE_BUCKET_SIZE

    (0..cohort_size).group_by do |submitted_count|
      exact_percentage = ((submitted_count * 100.0) / cohort_size).round(2)
      ((exact_percentage / bucket_size).round * bucket_size).to_f
    end
  end

  def distribution_percentage(body, status)
    body.fetch('status_distribution').find do |entry|
      entry.fetch('status') == status
    end.fetch('percentage')
  end

  def assert_peer_progress_not_found
    assert_equal 404, last_response.status

    body = last_response_body

    assert_json_limit_keys_to_exactly %w[error], body

    assert_equal(
      PeerProgressApi::NOT_FOUND_MESSAGE,
      body['error']
    )

    assert_private_no_store
  end

  def restore_env(name, value)
    if value.nil?
      ENV.delete(name)
    else
      ENV[name] = value
    end
  end

  def assert_private_no_store
    cache_control = last_response.headers.fetch('Cache-Control', '')

    assert_includes cache_control, 'private'
    assert_includes cache_control, 'no-store'
  end

  def assert_peer_progress_response_contract(body)
    assert_json_limit_keys_to_exactly RESPONSE_KEYS, body

    assert_kind_of Integer, body['task_definition_id']
    assert_kind_of Integer, body['unit_id']

    assert(
      body['target_grade'].nil? ||
        body['target_grade'].is_a?(Integer),
      'target_grade must be an integer or null'
    )

    assert(
      body['submitted_percentage'].nil? ||
        body['submitted_percentage'].is_a?(Numeric),
      'submitted_percentage must be numeric or null'
    )

    unless body['submitted_percentage'].nil?
      assert_operator body['submitted_percentage'], :>=, 0.0
      assert_operator body['submitted_percentage'], :<=, 100.0
    end

    assert(
      body['completed_percentage'].nil? ||
        body['completed_percentage'].is_a?(Numeric),
      'completed_percentage must be numeric or null'
    )

    unless body['completed_percentage'].nil?
      assert_operator body['completed_percentage'], :>=, 0.0
      assert_operator body['completed_percentage'], :<=, 100.0
    end

    if body['status_distribution'].nil?
      assert_equal false, body['distribution_available']
    else
      assert_equal true, body['distribution_available']
      assert_equal PeerProgressDistributionPolicy::STATUS_KEYS,
                   body['status_distribution'].pluck('status')

      body['status_distribution'].each do |entry|
        assert_json_limit_keys_to_exactly %w[status percentage], entry
        assert_kind_of String, entry['status']
        assert_kind_of Numeric, entry['percentage']
        assert_operator entry['percentage'], :>=, 0.0
        assert_operator entry['percentage'], :<=, 100.0
        assert_equal 0.0,
                     entry['percentage'] %
                     PeerProgressApi::PERCENTAGE_BUCKET_SIZE
      end
    end
    assert(
      body['distribution_unavailable_reason'].nil? ||
        body['distribution_unavailable_reason'].is_a?(String),
      'distribution_unavailable_reason must be a string or null'
    )

    %w[
      is_suppressed
      is_stale
      is_feature_enabled
      is_user_enabled
      distribution_available
    ].each do |key|
      assert_includes(
        [true, false],
        body.fetch(key),
        "#{key} must be a boolean"
      )
    end

    assert(
      body['unavailable_reason'].nil? ||
        body['unavailable_reason'].is_a?(String),
      'unavailable_reason must be a string or null'
    )

    unless body['last_updated_at'].nil?
      parsed_timestamp = nil

      assert_nothing_raised do
        parsed_timestamp = Time.iso8601(body['last_updated_at'])
      end

      assert_equal(
        0,
        parsed_timestamp.utc_offset,
        'last_updated_at must use UTC'
      )
    end

    assert_kind_of String, body['unavailable_message']
    assert_empty FORBIDDEN_KEYS & body.keys
    assert_private_no_store
  end
end
