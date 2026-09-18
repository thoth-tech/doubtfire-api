# frozen_string_literal: true

# Builds the public, privacy-preserving task-status distribution from an
# internal peer-progress snapshot.
#
# Quantising every status independently is not sufficient on its own. When the
# buckets are considered together, their sum constraint can occasionally make
# a raw count unique (for example, a cohort of 24 split into 6 and 18). Before
# releasing a vector, this policy assumes an observer knows the cohort size and
# verifies that every status still has at least two feasible raw counts.
class PeerProgressDistributionPolicy
  PERCENTAGE_BUCKET_SIZE = 10.0

  STATUS_KEYS = %w[
    not_started
    complete
    need_help
    working_on_it
    fix_and_resubmit
    feedback_exceeded
    redo
    discuss
    ready_for_feedback
    demonstrate
    fail
    time_exceeded
    assess_in_portfolio
    attention_required
    rediscuss
  ].freeze

  def self.quantised_percentage(value)
    ((value.to_f / PERCENTAGE_BUCKET_SIZE).round *
      PERCENTAGE_BUCKET_SIZE).to_f
  end

  def self.percentage(count:, cohort_size:)
    return nil unless cohort_size.to_i.positive?

    ((count.to_i * 100.0) / cohort_size).round(2)
  end

  def self.quantised_count_percentage(count:, cohort_size:)
    quantised_percentage(
      percentage(count: count, cohort_size: cohort_size)
    )
  end

  def self.build(status_counts:, cohort_size:)
    counts = normalized_counts(status_counts)
    return nil if counts.nil? || cohort_size.to_i <= 0
    return nil unless counts.values.sum == cohort_size

    distribution = STATUS_KEYS.map do |status|
      {
        status: status,
        percentage: quantised_count_percentage(
          count: counts.fetch(status),
          cohort_size: cohort_size
        )
      }
    end

    return nil unless preserves_count_ambiguity?(
      distribution: distribution,
      cohort_size: cohort_size
    )

    distribution
  end

  def self.valid_status_counts?(status_counts, cohort_size:)
    counts = normalized_counts(status_counts)

    counts.present? && counts.values.sum == cohort_size
  end

  def self.normalized_counts(status_counts)
    return nil unless status_counts.is_a?(Hash)

    counts = status_counts.transform_keys(&:to_s)
    return nil unless counts.keys.sort == STATUS_KEYS.sort
    return nil unless counts.values.all? do |value|
      value.is_a?(Integer) && value >= 0
    end

    counts
  end
  private_class_method :normalized_counts

  def self.preserves_count_ambiguity?(distribution:, cohort_size:)
    ranges = distribution.map do |entry|
      count_range_for_bucket(
        entry.fetch(:percentage),
        cohort_size
      )
    end

    minimum_sum = ranges.sum(&:begin)
    maximum_sum = ranges.sum(&:end)

    ranges.all? do |range|
      other_minimum = minimum_sum - range.begin
      other_maximum = maximum_sum - range.end
      feasible_minimum = [range.begin, cohort_size - other_maximum].max
      feasible_maximum = [range.end, cohort_size - other_minimum].min

      feasible_maximum - feasible_minimum >= 1
    end
  end
  private_class_method :preserves_count_ambiguity?

  # The quantised value is monotonic as count increases. Binary-searching both
  # edges avoids rebuilding every possible count bucket on every student GET:
  # detailed policy evaluation is O(statuses * log(cohort_size)), with no
  # unbounded cohort-size cache.
  def self.count_range_for_bucket(bucket, cohort_size)
    first = binary_search_count(cohort_size) do |count|
      quantised_count_percentage(
        count: count,
        cohort_size: cohort_size
      ) >= bucket
    end
    last = binary_search_count(cohort_size, upper: true) do |count|
      quantised_count_percentage(
        count: count,
        cohort_size: cohort_size
      ) <= bucket
    end

    first..last
  end
  private_class_method :count_range_for_bucket

  def self.binary_search_count(cohort_size, upper: false)
    low = 0
    high = cohort_size

    while low < high
      midpoint = (low + high + (upper ? 1 : 0)) / 2
      if yield(midpoint)
        upper ? low = midpoint : high = midpoint
      else
        upper ? high = midpoint - 1 : low = midpoint + 1
      end
    end

    low
  end
  private_class_method :binary_search_count
end
