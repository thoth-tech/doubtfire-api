# frozen_string_literal: true

require 'test_helper'

class UnitHubCalendarTest < ActiveSupport::TestCase
  setup do
    @student = FactoryBot.create(:user, :student)
    @unit = FactoryBot.create(:unit, with_students: false, task_count: 0)
    @project = @unit.enrol_student(@student, @unit.tutorials.first.campus)
    @webcal = Webcal.create!(user: @student, guid: SecureRandom.uuid)
    @session = @unit.unit_learning_sessions.create!(title: 'HelpHub', start_at: 1.day.from_now, end_at: 1.day.from_now + 1.hour,
                                                    published: true, join_url: 'https://teams.microsoft.com/l/meetup-join/example')
  end

  def session_events
    Icalendar::Calendar.parse(@webcal.to_ical.to_ical).first.events.select { |event| event.uid.to_s.start_with?('ontrack-session-') }
  end

  def test_calendar_is_explicit_opt_in_and_works_for_units_without_tasks
    assert_not @webcal.include_learning_sessions?
    assert_empty session_events
    @webcal.update!(include_learning_sessions: true)
    event = session_events.first
    assert_equal "ontrack-session-#{@session.id}-0", event.uid.to_s
    assert_equal @session.join_url, event.url.to_s
    assert_equal @session.start_at.utc.to_i, event.dtstart.to_time.to_i
  end

  def test_calendar_rechecks_withdrawal_and_exclusions
    @webcal.update!(include_learning_sessions: true)
    assert_equal 1, session_events.length
    @webcal.webcal_unit_exclusions.create!(unit: @unit)
    assert_empty session_events
    @webcal.webcal_unit_exclusions.destroy_all
    @project.update!(enrolled: false)
    assert_empty session_events
  end

  def test_other_units_and_drafts_never_enter_subscription
    @webcal.update!(include_learning_sessions: true)
    other = FactoryBot.create(:unit, with_students: false, task_count: 0)
    other.unit_learning_sessions.create!(title: 'Secret', start_at: 1.day.from_now, end_at: 1.day.from_now + 1.hour, published: true)
    @unit.unit_learning_sessions.create!(title: 'Draft', start_at: 1.day.from_now, end_at: 1.day.from_now + 1.hour)
    assert_equal 1, session_events.length
    @unit.update!(active: false)
    assert_empty session_events
  end

  def test_sessions_remain_available_on_the_final_day_of_a_unit
    @webcal.update!(include_learning_sessions: true)
    @unit.update!(end_date: Time.zone.today)
    assert_equal [@session.id], @webcal.learning_sessions.pluck(:id)
  end

  def test_cancellation_and_rescheduling_keep_stable_uid_and_remove_join_link
    @webcal.update!(include_learning_sessions: true)
    first = session_events.first
    @session.update!(start_at: @session.start_at + 1.hour, end_at: @session.end_at + 1.hour)
    moved = session_events.first
    assert_equal first.uid, moved.uid
    assert_not_equal first.dtstart, moved.dtstart
    assert_operator moved.sequence.to_i, :>, first.sequence.to_i
    @session.update!(cancelled: true)
    cancelled = session_events.first
    assert_equal first.uid, cancelled.uid
    assert_equal 'CANCELLED', cancelled.status.to_s
    assert_nil cancelled.url
    assert_not_includes cancelled.description.to_s, 'https://'
  end
end
