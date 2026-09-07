# frozen_string_literal: true

# Converts an internal whole-cohort snapshot into peer-only exact aggregates
# for one authenticated viewer. Public quantisation and vector ambiguity checks
# are applied afterwards; raw values from this policy never cross the API.
class PeerProgressViewerPolicy
  def self.viewer_context_current?(snapshot:, viewer_project:, viewer_task:)
    project_current = viewer_project.persisted? &&
                      viewer_project.updated_at.present? &&
                      viewer_project.updated_at <= snapshot.calculated_at
    task_current = !viewer_task.persisted? ||
                   (viewer_task.updated_at.present? &&
                     viewer_task.updated_at <= snapshot.calculated_at)

    project_current && task_current
  end

  def self.build(snapshot:, viewer_project:, viewer_task:)
    return nil unless viewer_context_current?(
      snapshot: snapshot,
      viewer_project: viewer_project,
      viewer_task: viewer_task
    )
    return nil unless snapshot.submitted_count.is_a?(Integer)
    return nil unless snapshot.submitted_count.between?(
      0,
      snapshot.cohort_size
    )
    return nil unless PeerProgressDistributionPolicy.valid_status_counts?(
      snapshot.status_counts,
      cohort_size: snapshot.cohort_size
    )

    peer_cohort_size = snapshot.cohort_size - 1
    return nil if peer_cohort_size.negative?

    counts = snapshot.status_counts.to_h.transform_keys(&:to_s).dup
    viewer_status = canonical_status(viewer_task.task_status_id)
    return nil if viewer_status.nil? || counts.fetch(viewer_status).zero?

    counts[viewer_status] -= 1
    submitted_count = snapshot.submitted_count
    submitted_count -= 1 if viewer_task.file_uploaded_at.present?
    return nil unless submitted_count.between?(0, peer_cohort_size)
    return nil unless PeerProgressDistributionPolicy.valid_status_counts?(
      counts,
      cohort_size: peer_cohort_size
    )

    {
      cohort_size: peer_cohort_size,
      submitted_count: submitted_count,
      status_counts: counts
    }
  end

  def self.public_metrics(peer_progress)
    counts = peer_progress.fetch(:status_counts)
    cohort_size = peer_progress.fetch(:cohort_size)
    distribution = PeerProgressDistributionPolicy.build(
      status_counts: counts,
      cohort_size: cohort_size
    )

    {
      submitted_percentage:
        PeerProgressDistributionPolicy.quantised_count_percentage(
          count: peer_progress.fetch(:submitted_count),
          cohort_size: cohort_size
        ),
      completed_percentage:
        PeerProgressDistributionPolicy.quantised_count_percentage(
          count: counts.fetch('complete'),
          cohort_size: cohort_size
        ),
      status_distribution: distribution,
      distribution_unavailable_reason:
        distribution.nil? ? 'privacy_protection' : nil
    }
  end

  def self.canonical_status(status_id)
    id = status_id.to_i
    expected_status = PeerProgressDistributionPolicy::STATUS_KEYS[id - 1]
    mapped_status = TaskStatus.id_to_key(id).to_s if expected_status.present?

    mapped_status if mapped_status == expected_status
  end
  private_class_method :canonical_status
end
