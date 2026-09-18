# frozen_string_literal: true

class PeerProgressSnapshot < ApplicationRecord
  # MariaDB exposes its JSON-compatible LONGTEXT column as text to the mysql2
  # adapter. Declaring the logical type explicitly keeps Hash casting identical
  # on MariaDB and native-JSON MySQL deployments.
  attribute :status_counts, :json

  belongs_to :unit,
             inverse_of: :peer_progress_snapshots

  belongs_to :task_definition,
             inverse_of: :peer_progress_snapshots

  validates :target_grade,
            presence: true,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0
            },
            uniqueness: {
              scope: %i[unit_id task_definition_id]
            }

  validates :submitted_percentage,
            numericality: {
              greater_than_or_equal_to: 0,
              less_than_or_equal_to: 100
            },
            allow_nil: true

  validates :submitted_count,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0
            },
            allow_nil: true

  validates :cohort_size,
            presence: true,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0
            }

  validates :calculated_at,
            presence: true

  validate :task_definition_belongs_to_unit
  validate :target_grade_enabled_for_unit
  validate :target_grade_covers_task
  validate :percentage_requires_non_empty_cohort
  validate :submitted_count_fits_cohort
  validate :status_counts_cover_the_cohort

  private

  def task_definition_belongs_to_unit
    return if unit.blank? || task_definition.blank?
    return if task_definition.unit_id == unit_id

    errors.add(
      :task_definition,
      'must belong to the same unit'
    )
  end

  def target_grade_enabled_for_unit
    return if unit.blank? || target_grade.nil?
    return if unit.grade_value?(target_grade)

    errors.add(
      :target_grade,
      'must be enabled for the unit'
    )
  end

  def target_grade_covers_task
    return if task_definition.blank? || target_grade.nil?
    return if target_grade >= task_definition.target_grade

    errors.add(
      :target_grade,
      'must be at least the task definition target grade'
    )
  end

  def percentage_requires_non_empty_cohort
    return if submitted_percentage.nil?
    return if cohort_size.nil?
    return if cohort_size.positive?

    errors.add(
      :submitted_percentage,
      'must be blank when cohort size is zero'
    )
  end

  def submitted_count_fits_cohort
    return if submitted_count.nil? || cohort_size.nil?
    return if submitted_count <= cohort_size

    errors.add(
      :submitted_count,
      'must not exceed the cohort size'
    )
  end

  def status_counts_cover_the_cohort
    return if status_counts.nil?

    keys_valid = status_counts.is_a?(Hash) &&
                 status_counts.keys.map(&:to_s).sort ==
                 PeerProgressDistributionPolicy::STATUS_KEYS.sort
    values_valid = status_counts.is_a?(Hash) &&
                   status_counts.values.all? do |value|
                     value.is_a?(Integer) && value >= 0
                   end

    unless keys_valid && values_valid
      errors.add(
        :status_counts,
        'must contain every supported task status with non-negative integer counts'
      )
      return
    end

    return if PeerProgressDistributionPolicy.valid_status_counts?(
      status_counts,
      cohort_size: cohort_size
    )

    errors.add(
      :status_counts,
      'must sum to the cohort size'
    )
  end
end
