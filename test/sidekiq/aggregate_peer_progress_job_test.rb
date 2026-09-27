# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class AggregatePeerProgressJobTest < ActiveSupport::TestCase
  def setup
    @active_unit = create_minimal_unit(active: true)
    @inactive_unit = create_minimal_unit(active: false)
    @disabled_unit = create_minimal_unit(
      active: true,
      peer_progress_enabled: false
    )
    @calculated_at = Time.zone.parse('2026-08-10 23:45:00')
  end

  def test_aggregates_the_requested_active_unit
    calls = []

    travel_to @calculated_at do
      PeerProgressAggregationService.stub(
        :call,
        lambda do |unit:, calculated_at:|
          calls << {
            unit: unit,
            calculated_at: calculated_at
          }
          []
        end
      ) do
        AggregatePeerProgressJob.new.perform(@active_unit.id)
      end
    end

    assert_equal 1, calls.length
    assert_equal @active_unit, calls.first[:unit]
    assert_equal @calculated_at, calls.first[:calculated_at]
  end

  def test_enqueues_one_job_for_each_enabled_active_unit_when_no_unit_id_is_given
    Sidekiq::Job.clear_all

    expected_unit_ids =
      Unit.active_units
          .where(peer_progress_enabled: true)
          .order(:id)
          .pluck(:id)

    assert_difference(
      -> { AggregatePeerProgressJob.jobs.size },
      expected_unit_ids.length
    ) do
      AggregatePeerProgressJob.new.perform
    end

    actual_unit_ids =
      AggregatePeerProgressJob.jobs
                              .last(expected_unit_ids.length)
                              .map { |job| job['args'].first }
                              .sort

    assert_equal expected_unit_ids, actual_unit_ids
    assert_not_includes actual_unit_ids, @inactive_unit.id
    assert_not_includes actual_unit_ids, @disabled_unit.id
  end

  def test_failure_for_one_unit_does_not_prevent_another_unit_job
    other_unit = create_minimal_unit(active: true)
    successful_unit_ids = []

    PeerProgressAggregationService.stub(
      :call,
      lambda do |unit:, **_kwargs|
        if unit.id == @active_unit.id
          raise StandardError, 'first unit failed'
        end

        successful_unit_ids << unit.id
        []
      end
    ) do
      assert_raises(StandardError) do
        AggregatePeerProgressJob.new.perform(@active_unit.id)
      end

      AggregatePeerProgressJob.new.perform(other_unit.id)
    end

    assert_equal [other_unit.id], successful_unit_ids
  end

  def test_skips_a_requested_inactive_unit
    calls = []

    PeerProgressAggregationService.stub(
      :call,
      lambda do |unit:, calculated_at:|
        calls << [unit, calculated_at]
        []
      end
    ) do
      AggregatePeerProgressJob.new.perform(@inactive_unit.id)
    end

    assert_empty calls
  end

  def test_skips_a_requested_unit_with_peer_progress_disabled
    calls = []

    PeerProgressAggregationService.stub(
      :call,
      lambda do |unit:, calculated_at:|
        calls << [unit, calculated_at]
        []
      end
    ) do
      AggregatePeerProgressJob.new.perform(@disabled_unit.id)
    end

    assert_empty calls
  end

  def test_sanitizes_the_error_when_requested_unit_does_not_exist
    missing_unit_id = Unit.maximum(:id).to_i + 10_000

    error = assert_raises(AggregatePeerProgressJob::AggregationError) do
      AggregatePeerProgressJob.new.perform(missing_unit_id)
    end

    assert_equal(
      "Peer progress aggregation failed for unit_id=#{missing_unit_id}: " \
      'ActiveRecord::RecordNotFound',
      error.message
    )
    assert_nil error.cause
  end

  def test_sanitizes_aggregation_errors_before_sidekiq_handles_them
    sensitive_message =
      'peer_username=private-peer name=Private Student ' \
      'email=private-peer@example.invalid student_id=987654321'
    start_log =
      "Starting peer progress aggregation for unit_id=#{@active_unit.id}..."
    failure_message =
      "Peer progress aggregation failed for unit_id=#{@active_unit.id}: " \
      'StandardError'
    logger = Minitest::Mock.new
    logger.expect(:info, nil, [start_log])
    logger.expect(:error, nil, [failure_message])
    job = AggregatePeerProgressJob.new

    PeerProgressAggregationService.stub(
      :call,
      lambda do |**_kwargs|
        raise StandardError, sensitive_message
      end
    ) do
      error = assert_raises(AggregatePeerProgressJob::AggregationError) do
        job.stub(:logger, logger) do
          job.perform(@active_unit.id)
        end
      end

      assert_equal failure_message, error.message
      assert_nil error.cause
      assert_not_includes error.message, sensitive_message
      assert_not_includes error.full_message, sensitive_message
    end

    assert_mock logger
    assert_equal 3, AggregatePeerProgressJob.get_sidekiq_options['retry']
  end

  def test_enqueues_only_the_unit_id
    assert_difference -> { AggregatePeerProgressJob.jobs.size }, 1 do
      AggregatePeerProgressJob.perform_async(@active_unit.id)
    end

    queued_job = AggregatePeerProgressJob.jobs.last

    assert_equal [@active_unit.id], queued_job['args']
  end

  def test_creates_a_snapshot_through_the_real_aggregation_service
    task_definition = create(
      :task_definition,
      unit: @active_unit,
      target_grade: 0,
      outcome_count: 0
    )

    projects = create_list(
      :project,
      2,
      unit: @active_unit,
      target_grade: 0,
      enrolled: true
    )

    create(
      :task,
      project: projects.first,
      task_definition: task_definition,
      task_status: TaskStatus.ready_for_feedback,
      file_uploaded_at: @calculated_at - 1.hour,
      submission_date: @calculated_at - 1.hour
    )

    travel_to @calculated_at do
      AggregatePeerProgressJob.new.perform(@active_unit.id)
    end

    snapshot = PeerProgressSnapshot.find_by!(
      unit: @active_unit,
      task_definition: task_definition,
      target_grade: 0
    )

    assert_equal 2, snapshot.cohort_size
    assert_equal 50.0, snapshot.submitted_percentage.to_f
    assert_equal @calculated_at, snapshot.calculated_at
  end

  private

  def create_minimal_unit(active:, peer_progress_enabled: true)
    create(
      :unit,
      active: active,
      peer_progress_enabled: peer_progress_enabled,
      with_students: false,
      task_count: 0,
      stream_count: 0,
      tutorials: 0,
      staff_count: 0,
      outcome_count: 0
    )
  end
end
