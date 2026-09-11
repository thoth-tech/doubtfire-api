# frozen_string_literal: true

require 'test_helper'

class PeerProgressDistributionPolicyTest < ActiveSupport::TestCase
  test 'returns every lifecycle status in canonical order' do
    distribution = PeerProgressDistributionPolicy.build(
      status_counts: safe_status_counts,
      cohort_size: 25
    )

    assert_equal PeerProgressDistributionPolicy::STATUS_KEYS,
                 distribution.pluck(:status)
    redo_entry = distribution.find do |entry|
      entry.fetch(:status) == 'redo'
    end
    resubmit_entry = distribution.find do |entry|
      entry.fetch(:status) == 'fix_and_resubmit'
    end

    assert_equal 10.0, redo_entry.fetch(:percentage)
    assert_equal 10.0, resubmit_entry.fetch(:percentage)
  end

  test 'suppresses a jointly identifying vector even though each bucket is independently ambiguous' do
    counts = empty_status_counts.merge(
      'not_started' => 6,
      'complete' => 18
    )

    assert_nil PeerProgressDistributionPolicy.build(
      status_counts: counts,
      cohort_size: 24
    )
  end

  test 'rejects missing extra negative and inconsistent counts' do
    missing = safe_status_counts.except('redo')
    extra = safe_status_counts.merge('unknown' => 0)
    negative = safe_status_counts.merge('redo' => -1, 'fail' => 4)

    [missing, extra, negative].each do |counts|
      assert_nil PeerProgressDistributionPolicy.build(
        status_counts: counts,
        cohort_size: 25
      )
    end

    assert_nil PeerProgressDistributionPolicy.build(
      status_counts: safe_status_counts,
      cohort_size: 26
    )
  end

  test 'binary count ranges match exhaustive quantisation without a cohort cache' do
    (21..200).each do |cohort_size|
      exhaustive = (0..cohort_size).group_by do |count|
        PeerProgressDistributionPolicy.quantised_count_percentage(
          count: count,
          cohort_size: cohort_size
        )
      end

      exhaustive.each do |bucket, counts|
        actual = PeerProgressDistributionPolicy.send(
          :count_range_for_bucket,
          bucket,
          cohort_size
        )

        assert_equal counts.min..counts.max, actual
      end
    end
  end

  private

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
end
