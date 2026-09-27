require 'test_helper'

class ProjectHistoryTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper

  def app
    Rails.application
  end

  def test_history_requires_authentication
    clear_auth_header

    get '/api/projects/history'

    assert_equal 419, last_response.status
    assert_not last_response_body.key?('hasProjects')
  end

  def test_user_without_projects_has_no_history
    student = FactoryBot.create(:user, :student)
    add_auth_header_for(user: student)

    get '/api/projects/history'

    assert_equal 200, last_response.status
    assert_equal({ 'hasProjects' => false }, last_response_body)
  end

  def test_active_project_counts_as_history
    student = FactoryBot.create(:user, :student, enrol_in: 1)
    add_auth_header_for(user: student)

    get '/api/projects/history'

    assert_equal 200, last_response.status
    assert_equal({ 'hasProjects' => true }, last_response_body)

    get '/api/projects'
    assert_equal 200, last_response.status
    assert_equal [student.projects.first.id], last_response_body.pluck('id')
  end

  def test_inactive_unit_counts_as_history_without_changing_project_listing
    student = FactoryBot.create(:user, :student, enrol_in: 1)
    student.projects.first.unit.update!(active: false)
    add_auth_header_for(user: student)

    get '/api/projects/history'

    assert_equal 200, last_response.status
    assert_equal({ 'hasProjects' => true }, last_response_body)

    get '/api/projects'
    assert_equal 200, last_response.status
    assert_empty last_response_body

    get '/api/projects', include_inactive: true
    assert_equal 200, last_response.status
    assert_equal [student.projects.first.id], last_response_body.pluck('id')
  end

  [true, false].each do |active|
    define_method("test_withdrawn_project_in_#{active ? 'active' : 'inactive'}_unit_counts_as_history") do
      student = FactoryBot.create(:user, :student, enrol_in: 1)
      project = student.projects.first
      project.update!(enrolled: false)
      project.unit.update!(active: active)
      add_auth_header_for(user: student)

      get '/api/projects/history'

      assert_equal 200, last_response.status
      assert_equal({ 'hasProjects' => true }, last_response_body)

      get '/api/projects', include_inactive: true
      assert_equal 200, last_response.status
      assert_empty last_response_body
    end
  end

  def test_query_parameters_cannot_select_another_users_history
    student = FactoryBot.create(:user, :student)
    other_student = FactoryBot.create(:user, :student, enrol_in: 1)
    add_auth_header_for(user: student)

    get '/api/projects/history', user_id: other_student.id, username: other_student.username

    assert_equal 200, last_response.status
    assert_equal({ 'hasProjects' => false }, last_response_body)

    add_auth_header_for(user: other_student)

    get '/api/projects/history', user_id: student.id, username: student.username

    assert_equal 200, last_response.status
    assert_equal({ 'hasProjects' => true }, last_response_body)
  end
end
