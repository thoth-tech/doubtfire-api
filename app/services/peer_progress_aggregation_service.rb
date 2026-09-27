# frozen_string_literal: true

# Calculates and stores task-level peer-progress snapshots for one unit.
#
# This service stores aggregate values only. It does not authorise students,
# apply the small-cohort display threshold, or expose API response data.
class PeerProgressAggregationService
  class UnsupportedTaskStatusError < StandardError; end

  def self.call(unit:, calculated_at: Time.zone.now)
    new(unit: unit, calculated_at: calculated_at).call
  end

  def initialize(unit:, calculated_at:)
    unless unit.is_a?(Unit) && unit.persisted?
      raise ArgumentError, 'unit must be a persisted Unit'
    end
    raise ArgumentError, 'calculated_at is required' if calculated_at.blank?

    @unit = unit
    @calculated_at = calculated_at
  end

  def call
    snapshots = []

    PeerProgressSnapshot.transaction do
      existing_snapshots = PeerProgressSnapshot.where(unit: unit).index_by do |snapshot|
        [snapshot.task_definition_id, snapshot.target_grade]
      end

      unit.grade_values.map(&:to_i).uniq.sort.each do |target_grade|
        cohort = unit.active_projects.where(target_grade: target_grade)
        cohort_size = cohort.count

        task_definitions = unit.task_definitions
                               .where('target_grade <= ?', target_grade)
                               .order(:id)

        submitted_counts = submitted_counts_for(
          cohort: cohort,
          task_definitions: task_definitions
        )
        status_counts = status_counts_for(
          cohort: cohort,
          task_definitions: task_definitions,
          cohort_size: cohort_size
        )

        task_definitions.each do |task_definition|
          key = [task_definition.id, target_grade]
          submitted_count = submitted_counts.fetch(task_definition.id, 0)

          snapshot = existing_snapshots[key] || PeerProgressSnapshot.new(
            unit: unit,
            task_definition: task_definition,
            target_grade: target_grade
          )

          snapshot.assign_attributes(
            cohort_size: cohort_size,
            submitted_count: submitted_count,
            submitted_percentage: percentage(
              submitted_count: submitted_count,
              cohort_size: cohort_size
            ),
            status_counts: status_counts.fetch(task_definition.id),
            calculated_at: calculated_at
          )

          snapshot.save!
          snapshots << snapshot
        end
      end
    end

    snapshots
  end

  private

  attr_reader :unit, :calculated_at

  def submitted_counts_for(cohort:, task_definitions:)
    Task
      .where(
        project_id: cohort.select(:id),
        task_definition_id: task_definitions.select(:id)
      )
      .where.not(file_uploaded_at: nil)
      .group(:task_definition_id)
      .distinct
      .count(:project_id)
  end

  def status_counts_for(cohort:, task_definitions:, cohort_size:)
    materialized_counts = Task
                          .where(
                            project_id: cohort.select(:id),
                            task_definition_id: task_definitions.select(:id)
                          )
                          .group(:task_definition_id, :task_status_id)
                          .distinct
                          .count(:project_id)

    task_definitions.to_h do |task_definition|
      counts = PeerProgressDistributionPolicy::STATUS_KEYS.index_with { 0 }

      materialized_counts.each do |(task_definition_id, status_id), count|
        next unless task_definition_id == task_definition.id

        status = canonical_status_for(status_id)
        counts[status] += count
      end

      missing_task_count = cohort_size - counts.values.sum
      if missing_task_count.negative?
        raise ArgumentError,
              'task status counts exceed the peer-progress cohort size'
      end

      counts['not_started'] += missing_task_count
      [task_definition.id, counts]
    end
  end

  def canonical_status_for(status_id)
    id = status_id.to_i
    expected_status = PeerProgressDistributionPolicy::STATUS_KEYS[id - 1]
    mapped_status = TaskStatus.id_to_key(id).to_s if expected_status.present?

    return mapped_status if expected_status.present? &&
                            mapped_status == expected_status

    # TaskStatus.id_to_key deliberately falls back to not_started for unknown
    # IDs. That is useful elsewhere, but would silently corrupt an aggregate
    # if a new lifecycle state were introduced without extending this policy.
    raise UnsupportedTaskStatusError,
          'peer-progress aggregation encountered an unsupported task status'
  end

  def percentage(submitted_count:, cohort_size:)
    return nil if cohort_size.zero?

    ((submitted_count * 100.0) / cohort_size).round(2)
  end
end
