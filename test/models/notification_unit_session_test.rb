# frozen_string_literal: true

require 'test_helper'

# Unit Hub sessions tell the unit when one moves or is cancelled, and remind
# people who opted in shortly before one starts.
class NotificationUnitSessionTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper
  include TestHelpers::PushNotificationHelper

  CHANGED = 'unit_session_changed'
  STARTING_SOON = 'unit_session_starting_soon'

  def app
    Rails.application
  end

  # The fan-out jobs carry until_executed locks. Sidekiq's fake mode never runs
  # a job a test clears, so a lock taken on push would outlive the test and turn
  # the same job away in the next one. Idempotency here comes from the dedupe
  # keys, which these tests check, so the locks are switched off.
  teardown do
    SidekiqUniqueJobs.config.enabled = @unique_jobs_enabled
  end

  setup do
    @unique_jobs_enabled = SidekiqUniqueJobs.config.enabled
    SidekiqUniqueJobs.config.enabled = false
    ActionMailer::Base.deliveries.clear
    Sidekiq::Worker.clear_all

    @unit = FactoryBot.create(:unit, with_students: false, task_count: 0, code: 'SIT333')
    @campus = @unit.tutorials.first.campus
    @convenor = @unit.unit_roles.where(role: Role.convenor).first.user
    @student = FactoryBot.create(:user, :student)
    @unit.enrol_student(@student, @campus)
    @withdrawn = FactoryBot.create(:user, :student)
    @unit.enrol_student(@withdrawn, @campus).update!(enrolled: false)

    # The unit factory also staffs the unit's tutorial. The convenor writes the
    # session below, so every other member of staff hears about it.
    @other_staff_ids = @unit.unit_roles.where(role: [Role.tutor, Role.convenor]).where.not(user_id: @convenor.id).pluck(:user_id)

    @start = Time.zone.parse('2030-03-05 17:00:00 +11:00')
    @session = @unit.unit_learning_sessions.create!(
      title: 'HelpHub', start_at: @start, end_at: @start + 1.hour, timezone: 'Australia/Melbourne',
      location: 'Building T, room 204', published: true, author: @convenor
    )
  end

  def run_jobs
    UnitSessionNotificationJob.drain
  end

  def notified(event = CHANGED)
    Notification.where(event: event)
  end

  def test_a_time_change_tells_enrolled_students_but_not_the_author
    travel_to(@start - 3.days) do
      @session.update!(start_at: @start + 1.hour, end_at: @start + 2.hours)
      run_jobs
    end

    assert_equal (@other_staff_ids + [@student.id]).sort, notified.pluck(:user_id).sort
    notification = notified.find_by(user: @student)
    assert_equal 'unit_hub', notification.notification_type
    assert_equal 'HelpHub in SIT333 has changed. Now: Tue 5 Mar at 6:00pm AEDT, Building T, room 204.', notification.message
    assert_equal "/unit-hub?unit=#{@unit.id}&session=#{@session.id}", notification.link
    assert_equal @session.id, notification.target_ids[:session_id]
    assert_equal @unit.id, notification.target_ids[:unit_id]
    assert_nil notification.target_ids[:announcement_id]
  end

  def test_other_staff_hear_about_it_when_their_category_is_on
    tutor = FactoryBot.create(:user, :tutor)
    @unit.employ_staff(tutor, Role.tutor)
    quiet_tutor = FactoryBot.create(:user, :tutor, receive_unit_hub_notifications: false)
    @unit.employ_staff(quiet_tutor, Role.tutor)

    travel_to(@start - 3.days) do
      @session.update!(location: 'Library, level 2')
      run_jobs
    end

    assert_equal (@other_staff_ids + [@student.id, tutor.id]).sort, notified.pluck(:user_id).sort
  end

  def test_a_cancellation_has_its_own_copy
    travel_to(@start - 3.days) do
      add_auth_header_for(user: @convenor)
      delete "/api/units/#{@unit.id}/sessions/#{@session.id}"
      assert_equal 200, last_response.status, last_response.body
      run_jobs
    end

    notification = notified.find_by(user: @student)
    assert_equal 'HelpHub in SIT333 on Tue 5 Mar at 5:00pm AEDT is cancelled.', notification.message
    assert_valid_push_payload(
      notification,
      expected_link: "/unit-hub?unit=#{@unit.id}&session=#{@session.id}",
      expected_body: 'A session in your unit has changed.'
    )
  end

  def test_a_weekly_cancellation_says_every_session_is_off
    @session.update_columns(recurrence: 'weekly', recurrence_until: (@start + 4.weeks).to_date) # rubocop:disable Rails/SkipsModelValidations
    travel_to(@start - 3.days) do
      @session.reload.update!(cancelled: true)
      run_jobs
    end

    assert_equal 'The weekly HelpHub sessions in SIT333 are cancelled.', notified.find_by(user: @student).message
  end

  def test_description_only_edits_drafts_and_past_sessions_tell_nobody
    travel_to(@start - 3.days) do
      @session.update!(description: 'Bring questions.')
      draft = @unit.unit_learning_sessions.create!(title: 'Draft', start_at: @start, end_at: @start + 1.hour)
      draft.update!(location: 'Somewhere')
      run_jobs
    end
    travel_to(@start + 1.week) do
      @session.update!(location: 'Too late')
      run_jobs
    end

    assert_equal 0, notified.count
  end

  def test_each_version_is_sent_once_however_often_the_job_runs
    travel_to(@start - 3.days) do
      @session.update!(location: 'Library, level 2')
      args = UnitSessionNotificationJob.jobs.last['args']
      run_jobs
      UnitSessionNotificationJob.new.perform(*args)

      assert_equal 1, notified.where(user: @student).count

      @session.update!(location: 'Library, level 3')
      run_jobs
    end

    assert_equal 2, notified.where(user: @student).count
  end

  def test_a_stale_time_change_is_dropped_once_the_session_is_cancelled
    travel_to(@start - 3.days) do
      @session.update!(location: 'Library, level 2')
      stale = UnitSessionNotificationJob.jobs.last['args']
      UnitSessionNotificationJob.clear
      @session.update!(cancelled: true)
      UnitSessionNotificationJob.new.perform(*stale)
      assert_equal 0, notified.count

      run_jobs
    end

    assert_match(/is cancelled\.\z/, notified.find_by(user: @student).message)
  end

  def test_the_change_and_cancellation_emails_render_with_details
    @student.update!(receive_unit_hub_email_notifications: true)
    @session.update!(join_url: 'https://teams.microsoft.com/l/meetup-join/example')

    travel_to(@start - 3.days) do
      @session.update!(location: 'Library, level 2')
      run_jobs
      NotificationEmailJob.drain
    end
    changed = ActionMailer::Base.deliveries.last
    html = changed.html_part.body.decoded

    assert_includes html, 'Session changed in SIT333'
    assert_includes html, 'Tue 5 Mar at 5:00pm AEDT to 6:00pm'
    assert_includes html, 'Library, level 2'
    assert_includes html, "/unit-hub?unit=#{@unit.id}&amp;session=#{@session.id}"
    assert_includes html, '/edit_profile'
    assert_includes changed.text_part.body.decoded, 'Where: Library, level 2'

    ActionMailer::Base.deliveries.clear
    travel_to(@start - 2.days) do
      @session.update!(cancelled: true)
      run_jobs
      NotificationEmailJob.drain
    end
    cancelled = ActionMailer::Base.deliveries.last
    html = cancelled.html_part.body.decoded

    assert_includes html, 'Session cancelled in SIT333'
    assert_includes html, 'This session will not run.'
    assert_includes html, 'Status:</strong> Cancelled'
    assert_not_includes html, 'teams.microsoft.com'
    assert_includes cancelled.text_part.body.decoded, 'is cancelled.'
  end

  def test_reminders_go_only_to_people_who_opted_in
    @student.update!(receive_unit_hub_session_reminders: true)
    other = FactoryBot.create(:user, :student)
    @unit.enrol_student(other, @campus)
    @withdrawn.update!(receive_unit_hub_session_reminders: true)
    @convenor.update!(receive_unit_hub_session_reminders: true)

    travel_to(@start - 20.minutes) { SendUnitSessionRemindersJob.new.perform }

    assert_equal [@student.id], notified(STARTING_SOON).pluck(:user_id)
    notification = notified(STARTING_SOON).first
    assert_equal 'HelpHub in SIT333 starts at 5:00pm AEDT (Building T, room 204).', notification.message
    assert_valid_push_payload(
      notification,
      expected_link: "/unit-hub?unit=#{@unit.id}&session=#{@session.id}",
      expected_body: 'A session in your unit starts soon.'
    )
  end

  def test_a_reminder_is_sent_once_across_runs_and_not_too_early_or_late
    @student.update!(receive_unit_hub_session_reminders: true)

    travel_to(@start - 45.minutes) { SendUnitSessionRemindersJob.new.perform }
    assert_equal 0, notified(STARTING_SOON).count

    [30, 25, 10, 5].each do |minutes|
      travel_to(@start - minutes.minutes) { SendUnitSessionRemindersJob.new.perform }
    end
    assert_equal 1, notified(STARTING_SOON).count

    travel_to(@start + 5.minutes) { SendUnitSessionRemindersJob.new.perform }
    assert_equal 1, notified(STARTING_SOON).count
  end

  def test_each_weekly_occurrence_gets_its_own_reminder
    @student.update!(receive_unit_hub_session_reminders: true)
    @session.update_columns(recurrence: 'weekly', recurrence_until: (@start + 4.weeks).to_date) # rubocop:disable Rails/SkipsModelValidations

    travel_to(@start - 10.minutes) { SendUnitSessionRemindersJob.new.perform }
    travel_to(@start + 1.week - 10.minutes) { SendUnitSessionRemindersJob.new.perform }

    assert_equal 2, notified(STARTING_SOON).count
  end

  def test_cancelled_and_unpublished_sessions_are_not_reminded
    @student.update!(receive_unit_hub_session_reminders: true)
    @session.update_columns(cancelled: true) # rubocop:disable Rails/SkipsModelValidations
    @unit.unit_learning_sessions.create!(title: 'Draft', start_at: @start, end_at: @start + 1.hour)

    travel_to(@start - 10.minutes) { SendUnitSessionRemindersJob.new.perform }

    assert_equal 0, notified(STARTING_SOON).count
  end

  def test_the_reminder_email_renders
    @student.update!(receive_unit_hub_session_reminders: true, receive_unit_hub_email_notifications: true)

    travel_to(@start - 10.minutes) do
      SendUnitSessionRemindersJob.new.perform
      NotificationEmailJob.drain
    end
    mail = ActionMailer::Base.deliveries.last

    assert_includes mail.html_part.body.decoded, 'Session starting soon in SIT333'
    assert_includes mail.html_part.body.decoded, 'Building T, room 204'
    assert_includes mail.html_part.body.decoded, 'session reminders are on'
    assert_includes mail.text_part.body.decoded, 'When: Tue 5 Mar at 5:00pm AEDT to 6:00pm'
  end

  def test_the_reminder_is_on_the_schedule
    schedule = YAML.load_file(Rails.root.join('config/schedule.yml'))

    assert_equal 'SendUnitSessionRemindersJob', schedule.dig('send_unit_session_reminders', 'class')
  end
end
