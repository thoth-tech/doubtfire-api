require 'test_helper'
require 'cgi'
require 'minitest/mock'

# EN-V06: a student submission notifies the responsible tutor once.
class NotificationTaskSubmittedTest < ActiveSupport::TestCase
  include TestHelpers::PushNotificationHelper

  setup do
    ActionMailer::Base.deliveries.clear
    NotificationEmailJob.clear

    @project = FactoryBot.create(:project)
    @unit = @project.unit
    @task_definition = @unit.task_definitions.first
    @task_definition.update!(
      start_date: 1.week.ago,
      target_date: 1.week.from_now
    )
    @task = @project.task_for_task_definition(@task_definition)
    @student = @project.student
    @tutor = @project.tutor_for(@task_definition)
  end

  def delivered_parts
    mail = ActionMailer::Base.deliveries.last

    {
      html: mail&.html_part&.body&.decoded.to_s,
      text: mail&.text_part&.body&.decoded.to_s
    }
  end

  def submit_for_marking(**options)
    @task.trigger_transition(
      trigger: 'ready_for_feedback',
      by_user: @student,
      **options
    )
  end

  def test_ready_for_marking_notifies_the_tutor_once_without_a_status_change_event
    assert_difference 'Notification.count', 1 do
      assert submit_for_marking
    end
    NotificationEmailJob.drain

    notification = Notification.recent_first.first

    assert_equal TaskStatus.ready_for_feedback, @task.reload.task_status
    assert_equal @tutor, notification.user
    assert_equal 'task', notification.notification_type
    assert_equal 'task_submitted', notification.event
    assert_equal 1, ActionMailer::Base.deliveries.count
    assert_equal [@tutor.email], ActionMailer::Base.deliveries.last.to

    assert_valid_push_payload(
      notification,
      expected_link: "/projects/#{@project.id}/dashboard/#{@task_definition.abbreviation}",
      expected_body: 'A task is ready for marking.'
    )
  end

  def test_message_and_templates_use_the_approved_tutor_facing_copy
    submit_for_marking
    NotificationEmailJob.drain

    notification = Notification.recent_first.first
    parts = delivered_parts
    product_name = Doubtfire::Application.config.institution[:product_name]
    expected_message =
      "#{@student.name} submitted #{@task_definition.name} for marking in #{product_name}."

    assert_equal expected_message, notification.message
    assert_equal "#{product_name}: New notification", ActionMailer::Base.deliveries.last.subject

    parts.each_value do |body|
      assert_not_empty body
      assert_includes body, "Hi #{@tutor.first_name}"
      assert_includes body, 'The submission and any assessment content are not included in this email.'
      assert_includes body, notification.link
      assert_includes body, '/edit_profile'
    end

    assert_includes parts[:text], expected_message
    assert_includes parts[:html], CGI.escapeHTML(expected_message)
  end

  def test_missing_tutor_is_safely_ignored
    @task.update!(task_status: TaskStatus.ready_for_feedback)

    @project.stub :tutor_for, nil do
      assert_no_difference 'Notification.count' do
        assert_nothing_raised do
          @task.notify_tutor_of_task_submission(
            @student,
            :student,
            TaskStatus.not_started.id,
            false
          )
        end
      end
    end

    assert_empty ActionMailer::Base.deliveries
  end

  def test_tutor_task_preference_suppresses_the_notification
    @tutor.update!(receive_task_notifications: false)

    assert_no_difference 'Notification.count' do
      assert submit_for_marking
    end

    assert_empty ActionMailer::Base.deliveries
  end

  def test_repeating_ready_for_marking_does_not_notify_again
    assert submit_for_marking
    ActionMailer::Base.deliveries.clear
    NotificationEmailJob.clear

    assert_no_difference 'Notification.count' do
      assert submit_for_marking
    end

    assert_empty ActionMailer::Base.deliveries
  end

  def test_internal_group_transition_does_not_amplify_the_notification
    assert_no_difference 'Notification.count' do
      assert submit_for_marking(group_transition: true)
    end

    assert_empty ActionMailer::Base.deliveries
  end

  def test_a_tutor_ready_for_feedback_transition_only_raises_the_existing_status_event
    assert_difference 'Notification.count', 1 do
      assert @task.trigger_transition(trigger: 'ready_for_feedback', by_user: @tutor)
    end
    NotificationEmailJob.drain

    notification = Notification.recent_first.first

    assert_equal 'task_status_changed', notification.event
    assert_equal @student, notification.user
    assert_equal [@student.email], ActionMailer::Base.deliveries.last.to
  end

  def test_notification_failure_does_not_stop_the_submission_transition
    result = nil

    NotificationService.stub :notify, ->(**_kwargs) { raise StandardError, 'notification exploded' } do
      result = submit_for_marking
    end

    assert result, 'the submission transition must still succeed'
    assert_equal TaskStatus.ready_for_feedback, @task.reload.task_status
  end
end
