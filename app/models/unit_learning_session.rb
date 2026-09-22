# frozen_string_literal: true

class UnitLearningSession < ApplicationRecord
  include UnitHubLinks

  KINDS = %w[helphub lecture seminar workshop other].freeze
  RECURRENCES = %w[none weekly].freeze

  belongs_to :unit
  belongs_to :author, class_name: 'User', optional: true

  validates :title, presence: true, length: { maximum: 200 }
  validates :description, length: { maximum: 20_000 }
  validates :location, length: { maximum: 300 }
  validates :kind, inclusion: { in: KINDS }
  validates :recurrence, inclusion: { in: RECURRENCES }
  validates :start_at, :end_at, :timezone, presence: true
  validates :published, :cancelled, inclusion: { in: [true, false] }
  validate :valid_schedule

  # Add calendar weeks in the named zone, not 604800 seconds in UTC: the local
  # HelpHub time stays constant across daylight saving changes.
  def occurrences(from:, to:)
    return [] unless start_at && end_at

    local_start = start_at.in_time_zone(timezone)
    local_end = end_at.in_time_zone(timezone)
    result = []
    27.times do |index|
      occurrence_start = local_start + index.weeks
      occurrence_end = local_end + index.weeks
      break if index.positive? && recurrence != 'weekly'
      break if recurrence == 'weekly' && occurrence_start.to_date > recurrence_until
      break if occurrence_start > to

      if occurrence_end >= from
        result << { occurrence_id: "#{id}-#{index}", start_at: occurrence_start, end_at: occurrence_end }
      end
    end
    result
  end

  private

  def valid_schedule
    begin
      TZInfo::Timezone.get(timezone.to_s)
    rescue TZInfo::InvalidTimezoneIdentifier
      errors.add(:timezone, 'must be an IANA time zone such as Australia/Melbourne')
      return
    end
    return unless start_at && end_at

    errors.add(:end_at, 'must be after the start and within 24 hours') unless end_at > start_at && end_at <= start_at + 24.hours
    return unless recurrence == 'weekly'

    first_date = start_at.in_time_zone(timezone).to_date
    unless recurrence_until && recurrence_until >= first_date && recurrence_until <= first_date + 6.months
      errors.add(:recurrence_until, 'must be on or after the first session and within six months')
    end
  end
end
