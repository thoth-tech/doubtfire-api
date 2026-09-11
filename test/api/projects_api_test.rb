require 'test_helper'
require 'date'
require './lib/helpers/database_populator'

class ProjectsApiTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper
  include TestHelpers::TestFileHelper

  def app
    Rails.application
  end

  def test_can_get_projects
    user = FactoryBot.create(:user, :student, enrol_in: 1)

    # Add username and auth_token to Header
    add_auth_header_for(user: user)

    get '/api/projects'
    assert_equal 200, last_response.status
  end

  def test_get_projects_with_streams_match
    unit = FactoryBot.create :unit, stream_count: 2, campus_count: 2, tutorials: 2, unenrolled_student_count: 0, part_enrolled_student_count: 0, inactive_student_count: 0
    project = unit.projects.first
    assert_equal 2, project.tutorial_enrolments.count

    # Add username and auth_token to Header
    add_auth_header_for(user: project.student)

    get '/api/projects'
    assert_equal 200, last_response.status
    assert_equal 1, last_response_body.count, last_response_body
  end

  def test_projects_returns_correct_number_of_projects
    user = FactoryBot.create(:user, :student, enrol_in: 2)

    # Add username and auth_token to Header
    add_auth_header_for(user: user)

    get '/api/projects'
    assert_equal 2, last_response_body.count
  end

  def test_projects_returns_correct_data
    user = FactoryBot.create(:user, :student, enrol_in: 2)

    # Add username and auth_token to Header
    add_auth_header_for(user: user)

    keys = %w[id unit campus_id user_id target_grade portfolio_available spec_con_days escalation_attempts_remaining]
    key_test = %w[campus_id target_grade spec_con_days]

    get '/api/projects'
    assert_equal 2, last_response_body.count, last_response_body
    last_response_body.each do |data|
      project = user.projects.find(data['id'])
      assert project.present?, data.inspect

      assert_json_limit_keys_to_exactly keys, data

      assert_json_matches_model(project, data, %w[campus_id target_grade campus_id])
      assert_json_matches_model(project.unit, data['unit'], %w[id code name active])

      assert_json_matches_model project, data, key_test
    end
  end

  def test_projects_with_task_definitions_uses_student_safe_serialization
    unit = FactoryBot.create(
      :unit,
      with_students: false,
      task_count: 0,
      allow_flexible_dates: true
    )
    common_start_date = unit.start_date + 1.week
    later_task = FactoryBot.create(
      :task_definition,
      unit: unit,
      abbreviation: 'CROSS-Z',
      start_date: common_start_date,
      plagiarism_report_url: 'https://staff.invalid/report',
      plagiarism_warn_pct: 99,
      tii_group_id: 'staff-only-group',
      similarity_language: 'staff-only-language',
      use_resources_for_jplag_base_code: true,
      lock_assessments_to_tutorial_stream: true,
      upload_requirements: [
        {
          'key' => 'file0',
          'name' => 'Student report',
          'type' => 'document',
          'tii_check' => true,
          'tii_pct' => 35
        }
      ]
    )
    earlier_task = FactoryBot.create(
      :task_definition,
      unit: unit,
      abbreviation: 'CROSS-A',
      start_date: common_start_date
    )
    grade_due_date = FactoryBot.create(
      :task_definition_grade_due_date,
      task_definition: later_task,
      target_grade: 1,
      target_due_date: later_task.target_date + 2.days,
      start_date: later_task.start_date + 1.day
    )
    student = FactoryBot.create(:user, :student)
    unit.enrol_student(student, unit.tutorials.first.campus)

    add_auth_header_for(user: student)

    get '/api/projects'
    assert_equal 200, last_response.status, last_response_body
    assert_not last_response_body.first.key?('tasks')
    assert_not last_response_body.first.fetch('unit').key?('task_definitions')

    get '/api/projects?include_task_definitions=true'
    assert_equal 200, last_response.status, last_response_body

    project_data = last_response_body.first
    assert project_data.key?('tasks')
    unit_data = project_data.fetch('unit')
    assert_equal true, unit_data.fetch('allow_flexible_dates')

    task_definitions = unit_data.fetch('task_definitions')
    assert_equal [earlier_task.id, later_task.id], task_definitions.pluck('id')

    task_definitions.each do |task_definition|
      %w[id abbreviation name description weighting target_grade upload_requirements].each do |key|
        assert task_definition.key?(key), "Expected student-safe task definition to include #{key}"
      end

      %w[
        plagiarism_report_url plagiarism_warn_pct tii_group_id similarity_language
        overseer_image_id use_resources_for_jplag_base_code
        lock_assessments_to_tutorial_stream restrict_status_updates created_at updated_at
      ].each do |key|
        assert_not task_definition.key?(key), "Student response exposed staff-only field #{key}"
      end
    end

    student_requirements = task_definitions.find do |task_definition|
      task_definition['id'] == later_task.id
    end.fetch('upload_requirements')
    assert_equal(
      [{ 'key' => 'file0', 'name' => 'Student report', 'type' => 'document' }],
      student_requirements
    )

    student_later_task = task_definitions.find do |task_definition|
      task_definition['id'] == later_task.id
    end
    grade_due_dates = student_later_task.fetch('grade_due_dates')
    assert_equal 1, grade_due_dates.length
    assert_equal grade_due_date.target_grade, grade_due_dates.first.fetch('target_grade')
    assert_equal grade_due_date.target_due_date.to_date,
                 Date.parse(grade_due_dates.first.fetch('target_due_date'))
    assert_equal grade_due_date.start_date.to_date,
                 Date.parse(grade_due_dates.first.fetch('start_date'))
  end

  def test_projects_with_task_definitions_exposes_privacy_safe_feedback_state
    project = FactoryBot.create(:project)
    unit = project.unit
    task_definition = unit.task_definitions.first
    task = project.task_for_task_definition(task_definition)
    student = project.student
    tutor = unit.main_convenor_user

    task.update!(task_status: TaskStatus.ready_for_feedback)
    task.add_status_comment(student, TaskStatus.ready_for_feedback)

    add_auth_header_for(user: student)

    get '/api/projects?include_task_definitions=true'
    assert_equal 200, last_response.status, last_response_body

    task_data = lambda do
      last_response_body
        .find { |data| data['id'] == project.id }
        .fetch('tasks')
        .find { |data| data['id'] == task.id }
    end

    assert_equal false, task_data.call.fetch('has_feedback')

    task.add_text_comment(student, 'Student follow-up')
    task.add_text_comment(tutor, '**Automated Message:** Automated feedback')

    get '/api/projects?include_task_definitions=true'
    assert_equal 200, last_response.status, last_response_body
    assert_equal false, task_data.call.fetch('has_feedback')

    task.add_text_comment(tutor, 'Manual tutor feedback')

    get '/api/projects?include_task_definitions=true'
    assert_equal 200, last_response.status, last_response_body

    response_task = task_data.call
    assert_equal true, response_task.fetch('has_feedback')

    %w[
      feedback feedback_text marker_notes feedback_author
      last_feedback_at has_unread_feedback
    ].each do |key|
      assert_not response_task.key?(key), "Student response exposed #{key}"
    end

    assert_not_includes last_response.body, 'Manual tutor feedback'
    assert_not_includes last_response.body, '**Automated Message:** Automated feedback'
  end

  def test_projects_feedback_state_is_scoped_to_authenticated_student
    unit = FactoryBot.create(
      :unit,
      with_students: false,
      task_count: 1,
      tutorials: 1
    )

    student = FactoryBot.create(:user, :student)
    other_student = FactoryBot.create(:user, :student)

    project = unit.enrol_student(student, unit.tutorials.first.campus)
    other_project = unit.enrol_student(other_student, unit.tutorials.first.campus)

    task_definition = unit.task_definitions.first
    project.task_for_task_definition(task_definition)
    other_task = other_project.task_for_task_definition(task_definition)

    other_task.update!(task_status: TaskStatus.ready_for_feedback)
    other_task.add_status_comment(other_student, TaskStatus.ready_for_feedback)
    other_task.add_text_comment(unit.main_convenor_user, 'Private feedback for other student')

    add_auth_header_for(user: student)

    get '/api/projects?include_task_definitions=true'
    assert_equal 200, last_response.status, last_response_body

    returned_project_ids = last_response_body.pluck('id')

    assert_includes returned_project_ids, project.id
    assert_not_includes returned_project_ids, other_project.id
    assert_not_includes last_response.body, 'Private feedback for other student'

    get "/api/projects/#{other_project.id}"

    assert_equal 403, last_response.status
    assert_not_includes last_response.body, 'Private feedback for other student'
  end

  def test_projects_with_inactive_task_definitions_avoids_per_record_queries
    student = FactoryBot.create(:user, :student)
    units = 2.times.map do
      unit = FactoryBot.create(
        :unit,
        with_students: false,
        task_count: 4,
        tutorials: 1,
        outcome_count: 0,
        active: true
      )
      project = unit.enrol_student(student, unit.tutorials.first.campus)
      unit.task_definitions.each do |task_definition|
        project.task_for_task_definition(task_definition)
      end
      unit
    end
    units.last.update!(active: false)
    add_auth_header_for(user: student)

    query_count = 0
    count_query = lambda do |_name, _started, _finished, _unique_id, payload|
      next if payload[:cached] || %w[SCHEMA TRANSACTION].include?(payload[:name])

      query_count += 1
    end

    ActiveSupport::Notifications.subscribed(count_query, 'sql.active_record') do
      get '/api/projects?include_inactive=true&include_task_definitions=true'
    end

    assert_equal 200, last_response.status, last_response_body
    assert_equal 2, last_response_body.length
    active_states = last_response_body.pluck('unit').pluck('active')
    assert_equal [false, true], (active_states.sort_by { |active| active ? 1 : 0 })
    assert_equal 8, (last_response_body.sum { |project| project.fetch('tasks').length })
    task_definition_count = last_response_body.sum do |project|
      project.fetch('unit').fetch('task_definitions').length
    end
    assert_equal 8, task_definition_count
    assert_operator query_count, :<=, 45,
                    "Expected a bounded project query graph, got #{query_count} SQL queries"
  end

  def test_get_project_response_is_correct
    user = FactoryBot.create(:user, :student, enrol_in: 1)
    project = user.projects.first

    # Add username and auth_token to Header
    add_auth_header_for(user: user)

    keys = %w[id unit unit_id user_id campus_id target_grade submitted_grade portfolio_files compile_portfolio portfolio_available uses_draft_learning_summary tasks tutorial_enrolments groups spec_con_days escalation_attempts_remaining]
    key_test = keys - %w[unit user_id portfolio_available tasks tutorial_enrolments groups]

    get "/api/projects/#{project.id}"
    assert_equal 200, last_response.status, last_response_body

    assert_json_limit_keys_to_exactly keys, last_response_body
    assert_json_matches_model project, last_response_body, key_test
  end

  def test_projects_works_with_inactive_units
    user = FactoryBot.create(:user, :student, enrol_in: 2)
    Unit.last.update(active: false)

    # Add username and auth_token to Header
    add_auth_header_for(user: user)

    get '/api/projects'
    assert_equal 1, last_response_body.count

    get '/api/projects?include_inactive=false'
    assert_equal 1, last_response_body.count

    get '/api/projects?include_inactive=true'

    assert_equal 2, last_response_body.count

    last_response_body.each do |data|
      project = user.projects.find(data['id'])
      assert project.present?, data.inspect

      assert_json_matches_model(project, data, %w[campus_id target_grade campus_id])
      assert_json_matches_model(project.unit, data['unit'], %w[code id name active])
    end
  end

  def test_submitted_grade_cant_change_after_submission
    user = FactoryBot.create(:user, :student, enrol_in: 1)
    project = user.projects.first

    data_to_put = {
      id: project.id,
      submitted_grade: 2
    }

    add_auth_header_for(user: user)

    put_json "/api/projects/#{project.id}", data_to_put
    project.reload

    assert_equal 200, last_response.status, last_response_body
    assert_equal user.projects.find(project.id).submitted_grade, 2

    keys = %w[campus_id target_grade submitted_grade compile_portfolio portfolio_available uses_draft_learning_summary]

    assert_json_limit_keys_to_exactly keys, last_response_body
    assert_json_matches_model project, last_response_body, keys

    DatabasePopulator.generate_portfolio(project)

    data_to_put['submitted_grade'] = 1

    put_json "/api/projects/#{project.id}", data_to_put

    assert_not_equal user.projects.find(project.id).submitted_grade, 1
    assert_equal 403, last_response.status
  end

  def test_download_portfolio
    project = FactoryBot.create(:project)
    unit = project.unit

    project.portfolio_production_date = Time.zone.now
    project.save

    `fallocate -l 10M #{project.portfolio_path}`

    assert File.exist?(project.portfolio_path)
    assert project.portfolio_exists?

    data_to_put = {
      as_attachment: true
    }

    add_auth_header_for(user: project.student)

    get "/api/submission/project/#{project.id}/portfolio", data_to_put
    assert_equal 200, last_response.status
    assert last_response.headers['Content-Disposition'].starts_with?('attachment; filename=')
    assert_equal 'Content-Disposition', last_response.headers['Access-Control-Expose-Headers']
    assert last_response.headers['Content-Type'] == 'application/pdf'
    assert 10_485_760, last_response.length

    `fallocate -l 11M #{project.portfolio_path}`
    get "/api/submission/project/#{project.id}/portfolio", data_to_put
    assert_equal 206, last_response.status
    assert 10_485_760, last_response.length

    data_to_put = {
      as_attachment: false
    }

    add_auth_header_for(user: project.student)
    header 'range', 'bytes=1000-1500'

    get "/api/submission/project/#{project.id}/portfolio", data_to_put
    assert 500, last_response.length
    assert_equal 206, last_response.status
    assert_nil last_response.headers['Content-Disposition']
    assert_equal 'Content-Range,Accept-Ranges', last_response.headers['Access-Control-Expose-Headers']
    assert last_response.headers['Content-Type'] == 'application/pdf'

    unit.destroy!
  ensure
    FileUtils.rm_f(project.portfolio_path)
  end
end
