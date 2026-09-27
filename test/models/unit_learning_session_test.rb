# frozen_string_literal: true

require 'test_helper'

class UnitLearningSessionTest < ActiveSupport::TestCase
  setup do
    @unit = FactoryBot.create(:unit, with_students: false, task_count: 0)
  end

  def test_weekly_occurrences_keep_local_time_across_daylight_saving
    session = @unit.unit_learning_sessions.create!(title: 'Thursday HelpHub', timezone: 'Australia/Melbourne',
      start_at: Time.iso8601('2026-10-01T17:00:00+10:00'), end_at: Time.iso8601('2026-10-01T18:00:00+10:00'),
      recurrence: 'weekly', recurrence_until: '2026-10-15')
    occurrences = session.occurrences(from: Time.iso8601('2026-09-01T00:00:00Z'), to: Time.iso8601('2026-11-01T00:00:00Z'))
    assert_equal 3, occurrences.length
    assert_equal [17, 17, 17], occurrences.map { |row| row[:start_at].hour }
    assert_equal [10.hours, 11.hours, 11.hours], occurrences.map { |row| row[:start_at].utc_offset }
    assert_equal [7, 6, 6], occurrences.map { |row| row[:start_at].utc.hour }
    assert_equal 3, occurrences.pluck(:occurrence_id).uniq.length
  end

  def test_weekly_recurrence_requires_a_bounded_end
    session = @unit.unit_learning_sessions.new(title: 'HelpHub', start_at: 1.day.from_now, end_at: 1.day.from_now + 1.hour, recurrence: 'weekly')
    assert_not session.valid?
    session.recurrence_until = 1.year.from_now.to_date
    assert_not session.valid?
    session.recurrence_until = 1.month.from_now.to_date
    assert session.valid?, session.errors.full_messages.join(', ')
  end

  def test_link_and_content_limits
    session = @unit.unit_learning_sessions.new(title: 'HelpHub', start_at: 1.day.from_now, end_at: 1.day.from_now + 1.hour)
    ["https://example.com\nBEGIN:VEVENT", '//example.com', 'data:text/html,test', 'https://a:b@example.com'].each do |url|
      session.join_url = url
      assert_not session.valid?, url
    end
    session.join_url = 'https://teams.microsoft.com/l/meetup-join/example?context=%7B%7D'
    assert session.valid?, session.errors.full_messages.join(', ')
    session.description = 'a' * 20_001
    assert_not session.valid?
  end
end
