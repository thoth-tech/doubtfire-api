require "test_helper"

class StudentTutorialEnrolmentApiTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper

  def app
    Rails.application
  end

  def setup
    @student = FactoryBot.create(:user, role: Role.student)
    @unit = FactoryBot.create(:unit)
    @project = FactoryBot.create(:project, unit: @unit, user: @student)
    @activity_type = FactoryBot.create(:activity_type)
    @tutorial_stream = FactoryBot.create(:tutorial_stream, unit: @unit, activity_type: @activity_type)
    @tutorial = FactoryBot.create(:tutorial, unit: @unit, tutorial_stream: @tutorial_stream)

    @tutorial.update!(campus_id: @project.campus_id)

    @task_def = FactoryBot.create(:task_definition,
      unit: @unit,
      tutorial_stream: @tutorial_stream,
      tutorial_self_enrolment_enabled: true,
      tutorial_self_enrolment_stream: @tutorial_stream
    )

    # Set headers with AuthHelper
    add_auth_header_for(user: @student)
  end

  test "POST enrolment creates new tutorial enrolment" do
    post "/api/projects/#{@project.id}/tutorial_enrolments", {
      task_definition_id: @task_def.id,
      tutorial_id: @tutorial.id
    }

    assert_equal 201, last_response.status
    response_data = last_response_body
    assert response_data["success"]
    assert_equal "Tutorial enrolment created successfully", response_data["message"]
  end

  test "POST enrolment fails for disabled self enrolment" do
    @task_def.update!(tutorial_self_enrolment_enabled: false)

    post "/api/projects/#{@project.id}/tutorial_enrolments", {
      task_definition_id: @task_def.id,
      tutorial_id: @tutorial.id
    }

    assert_equal 400, last_response.status
  end

  test "POST enrolment fails for unauthorized user" do
    other_student = FactoryBot.create(:user, role: Role.student)
    add_auth_header_for(user: other_student)

    post "/api/projects/#{@project.id}/tutorial_enrolments", {
      task_definition_id: @task_def.id,
      tutorial_id: @tutorial.id
    }

    assert_equal 401, last_response.status
  end

  test "GET enrolment returns current status when enrolled" do
    @project.enrol_in(@tutorial)

    get "/api/projects/#{@project.id}/tutorial_enrolments", {
      task_definition_id: @task_def.id
    }

    assert_equal 200, last_response.status
    response_data = last_response_body
    assert response_data["enrolled"]
    assert_equal @tutorial.id, response_data["tutorial"]["id"]
  end

  test "GET enrolment returns not enrolled status" do
    get "/api/projects/#{@project.id}/tutorial_enrolments", {
      task_definition_id: @task_def.id
    }

    assert_equal 200, last_response.status
    response_data = last_response_body
    assert_not response_data["enrolled"]
  end
end
