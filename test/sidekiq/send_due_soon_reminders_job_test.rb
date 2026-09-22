# frozen_string_literal: true

require 'test_helper'
# test_helper does not pull this in, and Object#stub comes from it.
require 'minitest/mock'

class SendDueSoonRemindersJobTest < ActiveSupport::TestCase
  include TestHelpers::PushNotificationHelper

  EVENT = 'task_due_soon'
  WINDOW_DAYS = SendDueSoonRemindersJob::WINDOW_DAYS

  setup do
    @unit = FactoryBot.create(:unit, task_count: 0)

    # This job sweeps every active unit there is, which is the whole point of
    # it. rake db:populate seeds four more, each with a cohort and task
    # definitions of its own, and their students would then land in every count
    # in this file: the first run of these tests expected 11 notifications and
    # got 27. Narrowing the world to the unit under test is what makes a plain
    # Notification.count assertion mean what it says.
    Unit.where.not(id: @unit.id).update_all(active: false)

    @task_def = FactoryBot.create(
      :task_definition,
      unit: @unit,
      target_grade: 0,
      start_date: Time.zone.now - 1.week,
      target_date: Time.zone.now + 2.days
    )

    ActionMailer::Base.deliveries.clear
  end

  # The students who most need a reminder are the ones who have not opened the
  # task, and OnTrack has no Task row for them until somebody touches it. A
  # sweep that read Task rows would miss exactly those people, and one that
  # called task_for_task_definition would silently create a row per student per
  # task every morning.
  def test_reminds_every_eligible_student_without_creating_tasks
    expected = @unit.active_projects.count

    assert_operator expected, :>=, 2
    assert_equal 0, @task_def.tasks.count

    assert_difference 'Notification.count', expected do
      assert_no_difference 'Task.count' do
        run_job
      end
    end

    assert_equal expected, ActionMailer::Base.deliveries.count
  end

  def test_does_not_remind_about_a_deadline_further_out
    @task_def.update!(target_date: Time.zone.now + (WINDOW_DAYS + 1).days)

    assert_no_difference 'Notification.count' do
      run_job
    end
  end

  def test_reminds_on_the_last_day_of_the_window
    @task_def.update!(target_date: Time.zone.now + WINDOW_DAYS.days)

    # The far edge, where an off by one turns the window into WINDOW_DAYS - 1
    # without anything else looking wrong.
    assert_difference 'Notification.count', @unit.active_projects.count do
      run_job
    end
  end

  def test_reminds_about_something_due_today
    @task_def.update!(target_date: Time.zone.now)

    assert_difference 'Notification.count', @unit.active_projects.count do
      run_job
    end
  end

  def test_does_not_remind_once_the_deadline_has_passed
    @task_def.update!(target_date: Time.zone.now - 1.day)

    # Overdue is a different message and a different ticket. A reminder saying
    # a task is due soon when it is already late is worse than saying nothing.
    assert_no_difference 'Notification.count' do
      run_job
    end
  end

  # This is the whole reason the job carries a duplicate guard. It runs every
  # morning and the task is still due soon tomorrow morning.
  def test_does_not_remind_the_same_student_twice
    run_job

    assert_no_difference 'Notification.count' do
      run_job
    end
  end

  def test_does_not_remind_a_withdrawn_student
    project = @unit.projects.find_by!(enrolled: false)
    project.update!(target_grade: 3)

    run_job

    assert_not Notification.exists?(user: project.student, event: EVENT)
  end

  def test_does_not_remind_for_an_inactive_unit
    @unit.update!(active: false)

    assert_no_difference 'Notification.count' do
      run_job
    end
  end

  def test_respects_task_notification_preference
    project = @unit.active_projects.first
    project.student.update!(receive_task_notifications: false)

    run_job

    assert_not Notification.exists?(user: project.student, event: EVENT)
  end

  def test_does_not_remind_a_student_the_task_is_not_assigned_to
    @task_def.update!(target_grade: 3)
    below = @unit.active_projects.where('projects.target_grade < 3')

    assert_operator below.count, :>, 0

    run_job

    below.each do |project|
      assert_not Notification.exists?(user: project.student, event: EVENT)
    end
  end

  # An extension moves the deadline for one student and nobody else, so the
  # date has to be read per student rather than off the task definition.
  def test_uses_the_students_own_extended_deadline
    project = @unit.active_projects.first
    project.task_for_task_definition(@task_def).update!(extensions: 1)

    run_job

    assert_not Notification.exists?(user: project.student, event: EVENT)

    # Everybody else is still on the original date and still gets one, so this
    # is the extension being read and not the whole sweep falling over.
    assert Notification.exists?(user: @unit.active_projects.second.student, event: EVENT)
  end

  # :discuss and :demonstrate mean the student has submitted and is waiting on a
  # tutor, so a reminder is both wrong and the kind of wrong that teaches people
  # to ignore notifications.
  def test_does_not_remind_about_a_task_that_is_waiting_on_a_tutor
    project = @unit.active_projects.first
    project.task_for_task_definition(@task_def).update!(task_status: TaskStatus.discuss)

    run_job

    assert_not Notification.exists?(user: project.student, event: EVENT)
  end

  # A unit with flexible dates gives each target grade its own deadline, and
  # that override applies before any Task row exists. Falling back to the task
  # definition's own target date for a student with no row is wrong by however
  # far apart those two dates are, and it is wrong in both directions: silence
  # when something is due in two days, or a reminder a week early.
  def test_uses_the_grade_deadline_when_the_unit_has_flexible_dates
    @unit.update!(allow_flexible_dates: true)
    @task_def.update!(target_date: Time.zone.now + 10.days)

    project = @unit.active_projects.find_by!(target_grade: 2)
    @task_def.grade_due_dates.create!(
      target_grade: 2,
      start_date: Time.zone.now - 1.week,
      target_due_date: Time.zone.now + 2.days
    )

    assert_equal 0, @task_def.tasks.count

    run_job

    assert Notification.exists?(user: project.student, event: EVENT)

    # Nobody else moved, so this is the override being read rather than the
    # whole window sliding.
    other = @unit.active_projects.where.not(target_grade: 2).first

    assert_not Notification.exists?(user: other.student, event: EVENT)
  end

  # Logging a failure and carrying on leaves perform successful, Sidekiq
  # schedules no retry, and a student whose task is due today is filtered out as
  # overdue tomorrow. That reminder is then gone for good.
  def test_a_failure_is_raised_so_sidekiq_retries
    raising = ->(**_args) { raise 'notification failed' }

    NotificationService.stub(:notify, raising) do
      assert_raises(RuntimeError) { run_job }
    end
  end

  def test_message_and_link_are_privacy_safe
    project = @unit.active_projects.first

    run_job

    notification = Notification.find_by!(user: project.student, event: EVENT)

    assert_includes notification.message, @task_def.abbreviation
    assert_includes notification.message, @unit.code

    # The date stays out, the same as task_due_date_changed. The row outlives
    # the deadline it describes, so "due on the 14th" is wrong a week later
    # while "due soon" only ever stops being interesting.
    assert_not_includes notification.message, @task_def.target_date.to_date.to_s
    assert_not_includes notification.message, @task_def.target_date.to_date.iso8601

    assert_equal(
      "/projects/#{project.id}/dashboard/#{@task_def.abbreviation}",
      notification.link
    )

    assert_valid_push_payload(
      notification,
      expected_link: "/projects/#{project.id}/dashboard/#{@task_def.abbreviation}"
    )
  end

  def test_event_specific_template_is_used
    run_job

    assert_includes delivered_body, 'The deadline is not included in this email'
  end

  def test_the_schedule_entry_points_at_this_job
    schedule = YAML.load_file(Rails.root.join('config/schedule.yml'))

    assert_equal(
      'SendDueSoonRemindersJob',
      schedule.dig('send_due_soon_reminders', 'class')
    )
  end

  private

  def run_job
    SendDueSoonRemindersJob.new.perform
    NotificationEmailJob.drain
  end

  def delivered_body
    mail = ActionMailer::Base.deliveries.last
    return '' if mail.nil?
    return mail.body.decoded unless mail.multipart?

    mail.parts.map { |part| part.body.decoded }.join("\n")
  end
end
