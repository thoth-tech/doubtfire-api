require 'test_helper'
require 'date'
require './lib/helpers/database_populator'

class ProjectsApiTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper

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

    keys = %w(id unit campus_id user_id target_grade portfolio_available)
    key_test = %w(campus_id target_grade)

    get '/api/projects'
    assert_equal 2, last_response_body.count, last_response_body
    last_response_body.each do |data|
      project = user.projects.find(data['id'])
      assert project.present?, data.inspect

      assert_json_limit_keys_to_exactly keys, data

      assert_json_matches_model(project, data, %w(campus_id target_grade campus_id))
      assert_json_matches_model(project.unit, data['unit'], %w(id code name active))

      assert_json_matches_model project, data, key_test
    end
  end

  def test_get_project_response_is_correct
    user = FactoryBot.create(:user, :student, enrol_in: 1)
    project = user.projects.first

    # Add username and auth_token to Header
    add_auth_header_for(user: user)

    keys = %w(id unit unit_id user_id campus_id target_grade submitted_grade portfolio_files compile_portfolio portfolio_available uses_draft_learning_summary tasks tutorial_enrolments groups task_outcome_alignments)
    key_test = keys - %w(unit user_id portfolio_available tasks tutorial_enrolments groups task_outcome_alignments)

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

      assert_json_matches_model(project, data, %w(campus_id target_grade campus_id))
      assert_json_matches_model(project.unit, data['unit'], %w(code id name active))
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

    keys = %w(campus_id target_grade submitted_grade compile_portfolio portfolio_available uses_draft_learning_summary)

    assert_json_limit_keys_to_exactly keys, last_response_body
    assert_json_matches_model project, last_response_body, keys

    DatabasePopulator.generate_portfolio(project)

    data_to_put['submitted_grade'] = 1

    put_json "/api/projects/#{project.id}", data_to_put

    assert_not_equal user.projects.find(project.id).submitted_grade, 1
    assert_equal 403, last_response.status
  end
end
