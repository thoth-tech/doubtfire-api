# frozen_string_literal: true

require 'test_helper'

class PeerProgressViewerPolicyTest < ActiveSupport::TestCase
  Snapshot = Struct.new(
    :submitted_count,
    :cohort_size,
    :status_counts,
    :calculated_at,
    keyword_init: true
  )
  ViewerTask = Struct.new(
    :task_status_id,
    :file_uploaded_at,
    :updated_at,
    :is_persisted,
    keyword_init: true
  ) do
    def persisted?
      is_persisted
    end
  end
  ViewerProject = Struct.new(
    :updated_at,
    :is_persisted,
    keyword_init: true
  ) do
    def persisted?
      is_persisted
    end
  end

  test 'subtracts the viewers known status upload and cohort membership' do
    calculated_at = Time.zone.now
    snapshot = Snapshot.new(
      cohort_size: 22,
      submitted_count: 1,
      status_counts: empty_status_counts.merge(
        'not_started' => 21,
        'complete' => 1
      ),
      calculated_at: calculated_at
    )
    viewer_task = ViewerTask.new(
      task_status_id: TaskStatus.complete.id,
      file_uploaded_at: 1.hour.ago,
      updated_at: calculated_at - 1.minute,
      is_persisted: true
    )

    result = PeerProgressViewerPolicy.build(
      snapshot: snapshot,
      viewer_project: viewer_project_for(snapshot),
      viewer_task: viewer_task
    )

    assert_equal 21, result.fetch(:cohort_size)
    assert_equal 0, result.fetch(:submitted_count)
    assert_equal 21, result.fetch(:status_counts).fetch('not_started')
    assert_equal 0, result.fetch(:status_counts).fetch('complete')
  end

  test 'treats a missing viewer task as not started and unsubmitted' do
    snapshot = Snapshot.new(
      cohort_size: 22,
      submitted_count: 21,
      status_counts: empty_status_counts.merge(
        'not_started' => 1,
        'complete' => 21
      ),
      calculated_at: Time.zone.now
    )
    viewer_task = ViewerTask.new(
      task_status_id: TaskStatus.not_started.id,
      file_uploaded_at: nil,
      updated_at: nil,
      is_persisted: false
    )

    result = PeerProgressViewerPolicy.build(
      snapshot: snapshot,
      viewer_project: viewer_project_for(snapshot),
      viewer_task: viewer_task
    )

    assert_equal 21, result.fetch(:cohort_size)
    assert_equal 21, result.fetch(:submitted_count)
    assert_equal 0, result.fetch(:status_counts).fetch('not_started')
    assert_equal 21, result.fetch(:status_counts).fetch('complete')
  end

  test 'fails closed when the viewer changed after the snapshot' do
    calculated_at = 1.hour.ago
    viewer_task = ViewerTask.new(
      task_status_id: TaskStatus.not_started.id,
      file_uploaded_at: nil,
      updated_at: calculated_at + 1.minute,
      is_persisted: true
    )

    snapshot = valid_snapshot(calculated_at: calculated_at)
    assert_not PeerProgressViewerPolicy.viewer_context_current?(
      snapshot: snapshot,
      viewer_project: viewer_project_for(snapshot),
      viewer_task: viewer_task
    )
    assert_nil PeerProgressViewerPolicy.build(
      snapshot: snapshot,
      viewer_project: viewer_project_for(snapshot),
      viewer_task: viewer_task
    )
  end

  test 'fails closed when project membership may have changed after snapshot' do
    snapshot = valid_snapshot(calculated_at: 1.hour.ago)
    viewer_project = ViewerProject.new(
      updated_at: snapshot.calculated_at + 1.minute,
      is_persisted: true
    )

    assert_not PeerProgressViewerPolicy.viewer_context_current?(
      snapshot: snapshot,
      viewer_project: viewer_project,
      viewer_task: missing_viewer_task
    )
    assert_nil PeerProgressViewerPolicy.build(
      snapshot: snapshot,
      viewer_project: viewer_project,
      viewer_task: missing_viewer_task
    )
  end

  test 'fails closed for an incomplete exact upload aggregate' do
    snapshot = valid_snapshot
    snapshot.submitted_count = nil

    assert_nil PeerProgressViewerPolicy.build(
      snapshot: snapshot,
      viewer_project: viewer_project_for(snapshot),
      viewer_task: missing_viewer_task
    )
  end

  test 'fails closed for a lifecycle status outside the canonical contract' do
    viewer_task = missing_viewer_task
    viewer_task.task_status_id = 16

    snapshot = valid_snapshot
    assert_nil PeerProgressViewerPolicy.build(
      snapshot: snapshot,
      viewer_project: viewer_project_for(snapshot),
      viewer_task: viewer_task
    )
  end

  private

  def valid_snapshot(calculated_at: Time.zone.now)
    Snapshot.new(
      cohort_size: 22,
      submitted_count: 0,
      status_counts: empty_status_counts.merge('not_started' => 22),
      calculated_at: calculated_at
    )
  end

  def missing_viewer_task
    ViewerTask.new(
      task_status_id: TaskStatus.not_started.id,
      file_uploaded_at: nil,
      updated_at: nil,
      is_persisted: false
    )
  end

  def viewer_project_for(snapshot)
    ViewerProject.new(
      updated_at: snapshot.calculated_at - 1.minute,
      is_persisted: true
    )
  end

  def empty_status_counts
    PeerProgressDistributionPolicy::STATUS_KEYS.index_with { 0 }
  end
end
