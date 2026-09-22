# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'
require 'tempfile'

class SendNewTaskAvailableNotificationsJobTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @unit = FactoryBot.create(
      :unit,
      with_students: false,
      task_count: 0,
      tutorials: 0,
      outcome_count: 0,
      staff_count: 0,
      campus_count: 1,
      active: true
    )
    Unit.where.not(id: @unit.id).update_all(active: false)

    @student = FactoryBot.create(
      :user,
      :student,
      receive_task_notifications: true
    )
    @project = FactoryBot.create(
      :project,
      unit: @unit,
      campus: Campus.first,
      user: @student,
      enrolled: true,
      target_grade: 2
    )
    @release_date = 2.days.from_now.beginning_of_day
    @task_definition = FactoryBot.create(
      :task_definition,
      unit: @unit,
      outcome_count: 0,
      target_grade: 1,
      start_date: @release_date,
      target_date: @release_date + 1.week
    )
    @task_definition.enable_new_task_notifications!
  end

  def test_notifies_on_release_date_without_creating_task_rows
    assert_no_difference 'Notification.count' do
      run_job
    end

    travel_to @release_date.noon do
      assert_difference 'Notification.count', 1 do
        assert_no_difference 'Task.count' do
          run_job
        end
      end

      assert_no_difference 'Notification.count' do
        run_job
      end
    end
  end

  def test_uses_grade_specific_start_date
    @unit.update!(allow_flexible_dates: true)
    @task_definition.update!(start_date: @release_date + 1.week)
    @task_definition.grade_due_dates.create!(
      target_grade: @project.target_grade,
      start_date: @release_date,
      target_due_date: @release_date + 1.week
    )

    travel_to @release_date.noon do
      assert_difference 'Notification.count', 1 do
        assert_no_difference 'Task.count' do
          run_job
        end
      end
    end
  end

  def test_skips_a_student_below_the_task_target_grade
    @project.update!(target_grade: 0)

    travel_to @release_date.noon do
      assert_no_difference 'Notification.count' do
        run_job
      end
    end
  end

  def test_uses_student_specific_start_date
    @unit.update!(allow_flexible_dates: true)
    @task_definition.update!(start_date: @release_date + 1.week)
    @project.task_for_task_definition(@task_definition).update!(
      target_start_date: @release_date
    )

    travel_to @release_date.noon do
      assert_difference 'Notification.count', 1 do
        assert_no_difference 'Task.count' do
          run_job
        end
      end
    end
  end

  def test_catches_up_after_a_missed_release_day
    @task_definition.update_column(:created_at, 1.month.ago)

    travel_to (@release_date + 1.day).noon do
      assert_difference 'Notification.count', 1 do
        run_job
      end
    end
  end

  def test_direct_job_repairs_a_failed_tracking_write_for_future_delivery
    @task_definition.update_column(:new_task_notifications_from, nil)
    marker_failure = -> { raise StandardError, 'temporary marker failure' }

    assert_difference -> { NewTaskAvailableNotificationJob.jobs.size }, 1 do
      @task_definition.stub(:enable_new_task_notifications!, marker_failure) do
        NewTaskAvailableNotificationJob.track_and_enqueue(@task_definition)
      end
    end

    assert_nil @task_definition.reload.new_task_notifications_from
    assert_no_difference 'Notification.count' do
      NewTaskAvailableNotificationJob.new.perform(@task_definition.id)
    end
    assert_not_nil @task_definition.reload.new_task_notifications_from

    travel_to @release_date.noon do
      assert_difference 'Notification.count', 1 do
        run_job
      end
    end
  end

  def test_future_csv_import_is_tracked_and_notified_on_release
    @task_definition.update_column(:new_task_notifications_from, nil)
    source_unit = FactoryBot.create(
      :unit,
      with_students: false,
      task_count: 0,
      tutorials: 0,
      outcome_count: 0,
      staff_count: 0,
      campus_count: 0,
      active: false,
      start_date: @unit.start_date,
      end_date: @unit.end_date
    )
    abbreviation = "CSV#{SecureRandom.hex(3)}"
    FactoryBot.create(
      :task_definition,
      unit: source_unit,
      outcome_count: 0,
      abbreviation: abbreviation,
      target_grade: 1,
      start_date: @release_date,
      target_date: @release_date + 1.week
    )
    csv = Tempfile.new(['future-task', '.csv'])
    csv.write(source_unit.task_definitions_csv)
    csv.rewind

    result = @unit.import_tasks_from_csv(csv)
    assert_empty result[:errors], result.inspect

    imported = @unit.task_definitions.find_by!(abbreviation: abbreviation)
    assert_not_nil imported.new_task_notifications_from
    notification_count = lambda do
      Notification.where(
        user: @student,
        event: 'new_task_available',
        link: "/projects/#{@project.id}/dashboard/#{imported.abbreviation}"
      ).count
    end

    travel_to (@release_date - 1.day).noon do
      assert_operator imported.start_date.to_date, :>, Time.zone.today
      assert_no_difference notification_count do
        assert_no_difference 'Task.count' do
          NewTaskAvailableNotificationJob.new.perform(imported.id)
        end
      end
    end

    travel_to @release_date.noon do
      assert_difference notification_count, 1 do
        assert_no_difference 'Task.count' do
          run_job
        end
      end
    end
  ensure
    csv&.close!
    source_unit&.destroy
  end

  def test_does_not_backfill_a_historical_task
    @task_definition.update_columns(
      created_at: 1.month.ago,
      start_date: Time.zone.today - 1.day,
      new_task_notifications_from: Time.current
    )

    assert_no_difference 'Notification.count' do
      run_job
    end
  end

  def test_does_not_backfill_a_recent_task_created_before_tracking_started
    @task_definition.update_columns(
      created_at: 1.day.ago,
      start_date: 1.month.ago,
      target_date: 3.weeks.ago,
      new_task_notifications_from: Time.current
    )

    assert_no_difference 'Notification.count' do
      run_job
    end
  end

  def test_accepts_a_rolling_writer_marker_just_after_creation
    @task_definition.update_columns(
      created_at: 2.days.ago,
      start_date: 3.days.ago,
      target_date: 1.week.from_now,
      new_task_notifications_from: 2.days.ago + 10.seconds
    )

    assert_difference 'Notification.count', 1 do
      run_job
    end
  end

  def test_ignores_inactive_units_and_withdrawn_projects
    travel_to @release_date.noon do
      @unit.update!(active: false)

      assert_no_difference 'Notification.count' do
        run_job
      end

      @unit.update!(active: true)
      @project.update!(enrolled: false)

      assert_no_difference 'Notification.count' do
        run_job
      end
    end
  end

  def test_catches_up_after_an_inactive_unit_is_reactivated
    @unit.update!(active: false)

    travel_to @release_date.noon do
      assert_no_difference 'Notification.count' do
        run_job
      end
    end

    @unit.update!(active: true)
    travel_to (@release_date + 1.day).noon do
      assert_difference 'Notification.count', 1 do
        run_job
      end
    end
  end

  def test_ignores_definitions_not_created_by_a_supported_workflow
    unsupported = FactoryBot.create(
      :task_definition,
      unit: @unit,
      outcome_count: 0,
      target_grade: 1,
      start_date: @release_date,
      target_date: @release_date + 1.week
    )
    assert_nil unsupported.reload.new_task_notifications_from
    @task_definition.update_column(:new_task_notifications_from, nil)

    travel_to @release_date.noon do
      assert_no_difference 'Notification.count' do
        run_job
      end
    end
  end

  def test_rollover_notifies_students_enrolled_before_the_copied_task_releases
    rolled_unit = @unit.rollover(
      nil,
      Time.zone.today + 4.weeks,
      Time.zone.today + 16.weeks,
      "ROLLED-#{SecureRandom.hex(3)}"
    )
    rolled_task = rolled_unit.task_definitions.find_by!(
      abbreviation: @task_definition.abbreviation
    )
    rolled_project = FactoryBot.create(
      :project,
      unit: rolled_unit,
      campus: Campus.first,
      user: @student,
      enrolled: true,
      target_grade: @project.target_grade
    )
    @unit.update!(active: false)

    travel_to rolled_task.start_date.to_date.noon do
      assert_difference 'Notification.count', 1 do
        run_job
      end

      notification = Notification.find_by!(
        user: @student,
        event: NewTaskAvailableNotificationJob::EVENT
      )
      assert_equal(
        "/projects/#{rolled_project.id}/dashboard/#{rolled_task.abbreviation}",
        notification.link
      )
    end
  ensure
    rolled_unit&.destroy
  end

  private

  def run_job
    SendNewTaskAvailableNotificationsJob.new.perform
  end
end
