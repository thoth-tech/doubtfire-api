# frozen_string_literal: true

require 'test_helper'

class PeerProgressAggregationServiceTest < ActiveSupport::TestCase
  def setup
    @unit = create(
      :unit,
      with_students: false,
      task_count: 0,
      stream_count: 0,
      tutorials: 0,
      staff_count: 0,
      outcome_count: 0
    )

    @pass_task = create(
      :task_definition,
      unit: @unit,
      target_grade: 0,
      outcome_count: 0
    )

    @credit_task = create(
      :task_definition,
      unit: @unit,
      target_grade: 1,
      outcome_count: 0
    )

    @calculated_at = Time.zone.parse('2026-08-10 10:00:00')
  end

  def test_calculates_percentage_for_enrolled_projects_in_the_same_target_grade
    projects = create_list(
      :project,
      4,
      unit: @unit,
      target_grade: 0,
      enrolled: true
    )

    projects.first(3).each do |project|
      create_submitted_task(
        project: project,
        task_definition: @pass_task
      )
    end

    other_grade = create(
      :project,
      unit: @unit,
      target_grade: 1,
      enrolled: true
    )

    create_submitted_task(
      project: other_grade,
      task_definition: @pass_task
    )

    withdrawn = create(
      :project,
      unit: @unit,
      target_grade: 0,
      enrolled: false
    )

    create_submitted_task(
      project: withdrawn,
      task_definition: @pass_task
    )

    run_service

    snapshot = find_snapshot(
      task_definition: @pass_task,
      target_grade: 0
    )

    assert_equal 4, snapshot.cohort_size
    assert_equal 3, snapshot.submitted_count
    assert_equal 75.0, snapshot.submitted_percentage.to_f
    assert_equal 1, snapshot.status_counts.fetch('not_started')
    assert_equal 3,
                 snapshot.status_counts.fetch('ready_for_feedback')
    assert_equal PeerProgressDistributionPolicy::STATUS_KEYS.sort,
                 snapshot.status_counts.keys.sort
    assert_equal 4, snapshot.status_counts.values.sum
    assert_equal @calculated_at, snapshot.calculated_at
  end

  def test_aggregates_every_canonical_task_status
    projects = create_list(
      :project,
      PeerProgressDistributionPolicy::STATUS_KEYS.length,
      unit: @unit,
      target_grade: 0,
      enrolled: true
    )

    projects.each_with_index do |project, index|
      create(
        :task,
        project: project,
        task_definition: @pass_task,
        task_status: TaskStatus.find(index + 1)
      )
    end

    run_service

    snapshot = find_snapshot(
      task_definition: @pass_task,
      target_grade: 0
    )

    assert_equal(
      PeerProgressDistributionPolicy::STATUS_KEYS.index_with { 1 },
      snapshot.status_counts
    )
  end

  def test_rejects_an_unknown_task_status_instead_of_counting_it_as_not_started
    unsupported_status = TaskStatus.create!(
      id: PeerProgressDistributionPolicy::STATUS_KEYS.length + 1,
      name: 'Future lifecycle state',
      description: 'Not yet included in the public peer-progress contract'
    )
    project = create(
      :project,
      unit: @unit,
      target_grade: 0,
      enrolled: true
    )
    create(
      :task,
      project: project,
      task_definition: @pass_task,
      task_status: unsupported_status
    )

    assert_raises(
      PeerProgressAggregationService::UnsupportedTaskStatusError
    ) { run_service }
  end

  def test_indexes_status_counts_by_task_definition_id_for_snapshot_upsert
    create(
      :project,
      unit: @unit,
      target_grade: 0,
      enrolled: true
    )

    assert_nothing_raised { run_service }

    snapshot = find_snapshot(
      task_definition: @pass_task,
      target_grade: 0
    )
    assert_equal 1, snapshot.status_counts.fetch('not_started')
  end

  def test_returns_a_genuine_zero_when_the_cohort_exists_but_nobody_has_submitted
    create_list(
      :project,
      4,
      unit: @unit,
      target_grade: 0,
      enrolled: true
    )

    run_service

    snapshot = find_snapshot(
      task_definition: @pass_task,
      target_grade: 0
    )

    assert_equal 4, snapshot.cohort_size
    assert_equal 0, snapshot.submitted_count
    assert_equal 0.0, snapshot.submitted_percentage.to_f
  end

  def test_returns_nil_percentage_when_the_cohort_is_empty
    run_service

    snapshot = find_snapshot(
      task_definition: @pass_task,
      target_grade: 3
    )

    assert_equal 0, snapshot.cohort_size
    assert_equal 0, snapshot.submitted_count
    assert_nil snapshot.submitted_percentage
    assert_equal(
      PeerProgressDistributionPolicy::STATUS_KEYS.index_with { 0 },
      snapshot.status_counts
    )
  end

  def test_only_creates_snapshots_for_tasks_applicable_to_the_target_grade
    create(
      :project,
      unit: @unit,
      target_grade: 0,
      enrolled: true
    )

    create(
      :project,
      unit: @unit,
      target_grade: 1,
      enrolled: true
    )

    run_service

    assert PeerProgressSnapshot.exists?(
      unit: @unit,
      task_definition: @pass_task,
      target_grade: 0
    )

    assert_not PeerProgressSnapshot.exists?(
      unit: @unit,
      task_definition: @credit_task,
      target_grade: 0
    )

    assert PeerProgressSnapshot.exists?(
      unit: @unit,
      task_definition: @pass_task,
      target_grade: 1
    )

    assert PeerProgressSnapshot.exists?(
      unit: @unit,
      task_definition: @credit_task,
      target_grade: 1
    )
  end

  def test_counts_uploads_regardless_of_the_current_task_status
    statuses = [
      TaskStatus.ready_for_feedback,
      TaskStatus.complete,
      TaskStatus.redo,
      TaskStatus.fix_and_resubmit
    ]

    projects = create_list(
      :project,
      statuses.length,
      unit: @unit,
      target_grade: 0,
      enrolled: true
    )

    projects.zip(statuses).each do |project, status|
      create_submitted_task(
        project: project,
        task_definition: @pass_task,
        task_status: status
      )
    end

    run_service

    snapshot = find_snapshot(
      task_definition: @pass_task,
      target_grade: 0
    )

    assert_equal statuses.length, snapshot.cohort_size
    assert_equal statuses.length, snapshot.submitted_count
    assert_equal 100.0, snapshot.submitted_percentage.to_f
  end

  def test_does_not_mix_projects_or_submissions_from_another_unit
    local_projects = create_list(
      :project,
      2,
      unit: @unit,
      target_grade: 0,
      enrolled: true
    )

    create_submitted_task(
      project: local_projects.first,
      task_definition: @pass_task
    )

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
      outcome_count: 0
    )

    other_projects = create_list(
      :project,
      4,
      unit: other_unit,
      target_grade: 0,
      enrolled: true
    )

    other_projects.each do |project|
      create_submitted_task(
        project: project,
        task_definition: other_task
      )
    end

    run_service

    snapshot = find_snapshot(
      task_definition: @pass_task,
      target_grade: 0
    )

    assert_equal 2, snapshot.cohort_size
    assert_equal 50.0, snapshot.submitted_percentage.to_f
    assert_not PeerProgressSnapshot.exists?(unit: other_unit)
  end

  def test_does_not_create_missing_task_rows
    create_list(
      :project,
      2,
      unit: @unit,
      target_grade: 0,
      enrolled: true
    )

    assert_no_difference('Task.count') do
      run_service
    end
  end

  def test_updates_existing_snapshots_without_creating_duplicates
    projects = create_list(
      :project,
      2,
      unit: @unit,
      target_grade: 0,
      enrolled: true
    )

    run_service
    snapshot_count = PeerProgressSnapshot.count

    create_submitted_task(
      project: projects.first,
      task_definition: @pass_task
    )

    PeerProgressAggregationService.call(
      unit: @unit,
      calculated_at: @calculated_at + 1.hour
    )

    snapshot = find_snapshot(
      task_definition: @pass_task,
      target_grade: 0
    )

    assert_equal snapshot_count, PeerProgressSnapshot.count
    assert_equal 50.0, snapshot.submitted_percentage.to_f
    assert_equal @calculated_at + 1.hour, snapshot.calculated_at
  end

  def test_rounds_percentages_to_two_decimal_places
    projects = create_list(
      :project,
      3,
      unit: @unit,
      target_grade: 0,
      enrolled: true
    )

    create_submitted_task(
      project: projects.first,
      task_definition: @pass_task
    )

    run_service

    snapshot = find_snapshot(
      task_definition: @pass_task,
      target_grade: 0
    )

    assert_equal 33.33, snapshot.submitted_percentage.to_f
  end

  def test_does_not_count_staff_assessment_without_a_student_upload
    project = create(
      :project,
      unit: @unit,
      target_grade: 0,
      enrolled: true
    )

    create(
      :task,
      project: project,
      task_definition: @pass_task,
      task_status: TaskStatus.complete,
      file_uploaded_at: nil,
      submission_date: @calculated_at - 1.hour,
      assessment_date: @calculated_at - 1.hour
    )

    run_service

    snapshot = find_snapshot(
      task_definition: @pass_task,
      target_grade: 0
    )

    assert_equal 1, snapshot.cohort_size
    assert_equal 0.0, snapshot.submitted_percentage.to_f
  end

  def test_counts_a_group_upload_for_each_participating_project
    group_unit = create(
      :unit,
      with_students: true,
      student_count: 2,
      unenrolled_student_count: 0,
      part_enrolled_student_count: 0,
      inactive_student_count: 0,
      task_count: 0,
      tutorials: 1,
      group_sets: 1,
      groups: [{ gs: 0, students: 2 }],
      outcome_count: 0
    )

    group_task = create(
      :task_definition,
      unit: group_unit,
      group_set: group_unit.group_sets.first,
      target_grade: 0,
      upload_requirements: [],
      start_date: 1.day.ago,
      outcome_count: 0
    )

    projects = group_unit.groups.first.projects.to_a
    projects.each { |project| project.update!(target_grade: 0) }

    submitting_task =
      projects.first.task_for_task_definition(group_task)

    contributions = projects.map do |project|
      {
        project_id: project.id,
        pct: 100 / projects.length,
        pts: 3
      }
    end

    submitting_task.create_submission_and_trigger_state_change(
      submitting_task.student,
      true,
      contributions,
      'ready_for_feedback'
    )

    PeerProgressAggregationService.call(
      unit: group_unit,
      calculated_at: @calculated_at
    )

    snapshot = PeerProgressSnapshot.find_by!(
      unit: group_unit,
      task_definition: group_task,
      target_grade: 0
    )

    assert_equal 2, snapshot.cohort_size
    assert_equal 100.0, snapshot.submitted_percentage.to_f

    projects.each do |project|
      task = project.tasks.find_by!(
        task_definition: group_task
      )

      assert task.file_uploaded_at.present?
    end
  end

  def run_service
    PeerProgressAggregationService.call(
      unit: @unit,
      calculated_at: @calculated_at
    )
  end

  def find_snapshot(task_definition:, target_grade:)
    PeerProgressSnapshot.find_by!(
      unit: @unit,
      task_definition: task_definition,
      target_grade: target_grade
    )
  end

  def create_submitted_task(
    project:,
    task_definition:,
    task_status: TaskStatus.ready_for_feedback
  )
    uploaded_at = @calculated_at - 1.hour

    create(
      :task,
      project: project,
      task_definition: task_definition,
      task_status: task_status,
      file_uploaded_at: uploaded_at,
      submission_date: uploaded_at
    )
  end
end
