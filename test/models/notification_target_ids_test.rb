require 'test_helper'

# The ids a client needs to open the page a notification is about. Worked out
# from the notifiable first and the link second, and nil once a record is gone.
class NotificationTargetIdsTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper

  def app
    Rails.application
  end

  setup do
    @project = FactoryBot.create(:project)
    @unit = @project.unit
    @task_definition = @unit.task_definitions.first
    @task = @project.task_for_task_definition(@task_definition)
    @student = @project.student
    @tutor = @project.tutor_for(@task_definition)
  end

  def task_link(project = @project, abbreviation = @task_definition.abbreviation)
    "/projects/#{project.id}/dashboard/#{ERB::Util.url_encode(abbreviation)}"
  end

  def notification_for(notifiable: nil, link: nil, user: @student)
    Notification.create!(
      user: user,
      notification_type: 'task',
      event: 'test_event',
      message: 'Something happened.',
      link: link,
      notifiable: notifiable
    )
  end

  def assert_task_ids(ids)
    assert_equal @unit.id, ids[:unit_id]
    assert_equal @project.id, ids[:project_id]
    assert_equal @student.id, ids[:student_id]
    assert_equal @task_definition.id, ids[:task_definition_id]
    assert_equal @task_definition.abbreviation, ids[:task_definition_abbr]
  end

  def test_a_comment_notification_names_the_comment_and_its_task
    comment = @task.add_text_comment(@student, 'A question for my tutor')
    ids = Notification.find_by!(notifiable: comment).target_ids

    assert_task_ids(ids)
    assert_equal @task.id, ids[:task_id]
    assert_equal comment.id, ids[:comment_id]
    assert_nil ids[:group_id]
  end

  def test_a_task_notification_names_the_task
    ids = notification_for(notifiable: @task, link: task_link).target_ids

    assert_task_ids(ids)
    assert_equal @task.id, ids[:task_id]
    assert_nil ids[:comment_id]
  end

  def test_a_link_only_notification_is_resolved_from_its_link
    ids = notification_for(link: task_link).target_ids

    assert_task_ids(ids)
    assert_equal @task.id, ids[:task_id]
  end

  def test_a_task_link_with_no_task_row_yet_still_names_the_definition
    other_definition = @unit.task_definitions.second
    Task.where(project: @project, task_definition: other_definition).delete_all

    ids = notification_for(link: task_link(@project, other_definition.abbreviation)).target_ids

    assert_equal other_definition.id, ids[:task_definition_id]
    assert_nil ids[:task_id]
  end

  def test_a_project_link_names_the_project_and_unit_only
    ids = notification_for(link: "/projects/#{@project.id}/dashboard").target_ids

    assert_equal @unit.id, ids[:unit_id]
    assert_equal @project.id, ids[:project_id]
    assert_equal @student.id, ids[:student_id]
    assert_nil ids[:task_definition_id]
    assert_nil ids[:task_id]
  end

  def test_a_portfolio_notification_on_the_project_names_the_student
    ids = notification_for(notifiable: @project, link: "/projects/#{@project.id}/dashboard", user: @tutor).target_ids

    assert_equal @project.id, ids[:project_id]
    assert_equal @student.id, ids[:student_id]
  end

  def test_a_group_change_names_the_group_and_the_project
    group_set = FactoryBot.create(:group_set, unit: @unit)
    group = FactoryBot.create(:group, group_set: group_set)

    ids = notification_for(notifiable: group, link: "/projects/#{@project.id}/groups").target_ids

    assert_equal group.id, ids[:group_id]
    assert_equal @project.id, ids[:project_id]
  end

  def test_a_missing_project_leaves_every_id_nil
    ids = notification_for(link: '/projects/999999999/dashboard/1.1P').target_ids

    assert(ids.values.all?(&:nil?), ids.inspect)
  end

  def test_an_unknown_task_abbreviation_leaves_the_task_ids_nil
    ids = notification_for(link: task_link(@project, 'NOPE')).target_ids

    assert_equal @project.id, ids[:project_id]
    assert_nil ids[:task_definition_id]
    assert_nil ids[:task_definition_abbr]
    assert_nil ids[:task_id]
  end

  def test_a_general_notification_with_no_link_has_no_target
    ids = notification_for.target_ids

    assert(ids.values.all?(&:nil?), ids.inspect)
  end

  # web_path mirrors the web client's notification-target.ts, so an email
  # button opens the page the bell would.
  def test_web_path_for_a_student_opens_their_own_pages
    comment_link = "#{task_link}/feedback"
    project = "/projects/#{@project.id}"
    abbreviation = ERB::Util.url_encode(@task_definition.abbreviation)

    {
      ['task_comment_created', 'feedback', comment_link] => "#{project}/dashboard/#{abbreviation}/feedback",
      ['extension_assessed', 'extension', task_link] => "#{project}/dashboard/#{abbreviation}/feedback",
      ['task_status_changed', 'task', task_link] => "#{project}/dashboard/#{abbreviation}",
      ['group_membership_changed', 'general', "#{project}/groups"] => "#{project}/groups",
      ['tutorial_changed', 'general', "#{project}/dashboard"] => "#{project}/tutorials",
      ['portfolio_received', 'portfolio', "#{project}/dashboard"] => "#{project}/portfolio"
    }.each do |(event, type, link), expected|
      notification = Notification.new(user: @student, event: event, notification_type: type, message: 'x', link: link)

      assert_equal expected, notification.web_path, event
    end
  end

  def test_web_path_for_staff_opens_the_inbox_or_the_staff_portfolio_view
    abbreviation = ERB::Util.url_encode(@task_definition.abbreviation)
    inbox = "/units/#{@unit.id}/tasks/inbox/#{@student.id}/#{abbreviation}?students=all"

    %w[task_submitted task_help_requested extension_requested task_comment_created].each do |event|
      notification = Notification.new(user: @tutor, event: event, notification_type: 'task', message: 'x', link: task_link)

      assert_equal inbox, notification.web_path, event
    end

    portfolio = Notification.new(
      user: @tutor, event: 'portfolio_submitted', notification_type: 'portfolio', message: 'x',
      link: "/projects/#{@project.id}/dashboard", notifiable: @project
    )

    assert_equal "/units/#{@unit.id}/students/portfolios/#{@project.id}", portfolio.web_path
  end

  def test_web_path_falls_back_to_the_link_when_the_target_is_gone
    gone = Notification.new(user: @student, event: 'task_comment_created', notification_type: 'feedback',
                            message: 'x', link: task_link(@project, 'NOPE'))

    assert_equal task_link(@project, 'NOPE'), gone.web_path
    assert_nil Notification.new(user: @student, event: 'general_event', notification_type: 'general', message: 'x').web_path
  end

  def test_the_api_adds_the_ids_beside_the_existing_fields
    notification = notification_for(notifiable: @task, link: task_link)

    add_auth_header_for(user: @student)
    get '/api/notifications'

    assert_equal 200, last_response.status
    row = JSON.parse(last_response.body).find { |json| json['id'] == notification.id }

    assert_equal task_link, row['link'], 'the existing link is unchanged'
    assert_equal 'test_event', row['event']
    assert_equal @unit.id, row['unit_id']
    assert_equal @project.id, row['project_id']
    assert_equal @student.id, row['student_id']
    assert_equal @task_definition.id, row['task_definition_id']
    assert_equal @task_definition.abbreviation, row['task_definition_abbr']
    assert_equal @task.id, row['task_id']
    assert row.key?('comment_id')
    assert row.key?('group_id')
  end
end
