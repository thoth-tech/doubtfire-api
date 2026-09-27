require 'test_helper'
require 'cgi'

# A student moving a task to Need Help notifies the responsible tutor once.
class NotificationTaskHelpRequestedTest < ActiveSupport::TestCase
  include TestHelpers::PushNotificationHelper

  setup do
    ActionMailer::Base.deliveries.clear
    NotificationEmailJob.clear

    @project = FactoryBot.create(:project)
    @unit = @project.unit
    @task_definition = @unit.task_definitions.first
    @task = @project.task_for_task_definition(@task_definition)
    @student = @project.student

    # A tutor of their own, so the recipient is not just the main convenor
    # that tutor_for falls back to.
    tutor_role = @unit.employ_staff(FactoryBot.create(:user, :tutor), Role.tutor)
    @project.enrol_in(FactoryBot.create(:tutorial, unit: @unit, campus: @project.campus, unit_role: tutor_role))
    @tutor = tutor_role.user
    ActionMailer::Base.deliveries.clear
    NotificationEmailJob.clear
  end

  def delivered_parts
    mail = ActionMailer::Base.deliveries.last

    {
      html: mail&.html_part&.body&.decoded.to_s,
      text: mail&.text_part&.body&.decoded.to_s
    }
  end

  def ask_for_help(by_user: @student, **options)
    @task.trigger_transition(trigger: 'need_help', by_user: by_user, **options)
  end

  def test_need_help_notifies_the_tutor_once
    assert_equal @tutor, @project.tutor_for(@task_definition), 'guard: the task must have its own tutor'

    assert_difference 'Notification.count', 1 do
      assert ask_for_help
    end
    NotificationEmailJob.drain

    notification = Notification.recent_first.first
    product_name = Doubtfire::Application.config.institution[:product_name]
    expected_message = "#{@student.name} asked for help with #{@task_definition.name} in #{product_name}."

    assert_equal TaskStatus.need_help, @task.reload.task_status
    assert_equal @tutor, notification.user
    assert_equal 'task', notification.notification_type
    assert_equal 'task_help_requested', notification.event
    assert_equal expected_message, notification.message
    assert_equal @task, notification.notifiable

    assert_valid_push_payload(
      notification,
      expected_link: "/projects/#{@project.id}/dashboard/#{@task_definition.abbreviation}",
      expected_body: 'A student asked for help with a task.'
    )

    assert_equal 1, ActionMailer::Base.deliveries.count
    assert_equal [@tutor.email], ActionMailer::Base.deliveries.last.to

    parts = delivered_parts

    parts.each_value do |body|
      assert_not_empty body
      assert_includes body, "Hi #{@tutor.first_name}"
      assert_includes body, notification.web_path
    end

    assert_includes parts[:text], expected_message
    assert_includes parts[:html], CGI.escapeHTML(expected_message)
  end

  # Staff other than the student's tutor, so it is the student-only check that
  # stops this and not the rule against notifying yourself.
  def test_staff_setting_need_help_does_not_ask_the_tutor_for_help
    assert_difference 'Notification.count', 1 do
      assert ask_for_help(by_user: @unit.main_convenor_user)
    end

    # The one notification is EN-E02 telling the student about a staff change.
    notification = Notification.recent_first.first

    assert_equal 'task_status_changed', notification.event
    assert_equal @student, notification.user
  end

  def test_an_unchanged_status_does_not_notify_again
    assert ask_for_help

    assert_no_difference 'Notification.count' do
      assert ask_for_help
    end
  end

  def test_an_internal_group_transition_does_not_notify
    assert_no_difference 'Notification.count' do
      assert ask_for_help(group_transition: true)
    end
  end

  # Uploading group work with the Need Help trigger moves every member's task,
  # but only the uploader's own task should reach a tutor.
  def test_a_group_upload_asking_for_help_notifies_once
    unit = FactoryBot.create(:unit, student_count: 3)
    group_set = GroupSet.create!(name: 'help request group set', unit: unit)
    group = Group.create!(group_set: group_set, name: 'help request group', tutorial: unit.tutorials.first)
    projects = unit.active_projects.first(3)
    projects.each { |project| group.add_member(project) }

    task_definition = FactoryBot.create(
      :task_definition,
      unit: unit,
      group_set: group_set,
      start_date: 1.week.ago,
      target_date: 1.week.from_now
    )
    uploader = projects.first
    uploader_task = uploader.task_for_task_definition(task_definition)

    assert_difference -> { Notification.where(event: 'task_help_requested').count }, 1 do
      uploader_task.create_submission_and_trigger_state_change(uploader.student, true, nil, 'need_help')
    end

    notification = Notification.where(event: 'task_help_requested').last

    assert_equal uploader.tutor_for(task_definition), notification.user
    assert_equal uploader_task, notification.notifiable

    projects.each do |project|
      assert_equal TaskStatus.need_help, project.task_for_task_definition(task_definition).reload.task_status,
                   'guard: the upload has to reach every member task'
    end
  end

  def test_the_tutor_task_preference_suppresses_it
    @tutor.update!(receive_task_notifications: false)

    assert_no_difference 'Notification.count' do
      assert ask_for_help
    end
  end
end
