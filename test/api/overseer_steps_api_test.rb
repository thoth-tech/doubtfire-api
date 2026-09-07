require 'test_helper'

class OverseerStepsApiTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper
  include TestHelpers::OverseerTestHelper

  def app
    Rails.application
  end

  def setup
    setup_overseer_enabled

    @unit = FactoryBot.create(:unit, with_students: false)
    @task_definition = @unit.task_definitions.first
    @other_task_definition = @unit.task_definitions.where.not(id: @task_definition.id).first

    @owner = FactoryBot.create(:user, :student)
    @owner_project = @unit.enrol_student(@owner, nil)

    @other_student = FactoryBot.create(:user, :student)
    @other_project = @unit.enrol_student(@other_student, nil)

    @tutor = FactoryBot.create(:user, :tutor)
    @unit.employ_staff(@tutor, Role.tutor)

    @overseer_step = OverseerStep.create!(
      task_definition: @task_definition,
      name: 'compile',
      display_name: 'Compile',
      step_type: 'build',
      timeout: 30,
      sort_order: 0
    )

    @assessment = create_assessment_for(@owner_project)
    @result = @assessment.overseer_step_results.first
  end

  #
  # Create an overseer assessment, with one step result, for the given project
  #
  def create_assessment_for(project)
    task = project.task_for_task_definition(@task_definition)
    submission_history = FactoryBot.create(:submission_history, task: task)
    assessment = FactoryBot.create(:overseer_assessment, submission_history: submission_history)

    OverseerStepResult.create!(
      overseer_assessment: assessment,
      overseer_step: @overseer_step,
      exit_status: 0,
      pass: true,
      feedback_message: 'All good'
    )

    assessment
  end

  def results_url(project, assessment, task_definition = @task_definition)
    "/api/projects/#{project.id}/task_definitions/#{task_definition.id}/overseer_assessments_results/#{assessment.id}"
  end

  def test_student_can_get_results_for_their_own_overseer_assessment
    add_auth_header_for(user: @owner)

    get results_url(@owner_project, @assessment)

    assert_equal 200, last_response.status, last_response.body
    assert_equal 1, last_response_body.count, last_response.body
    assert_equal @result.id, last_response_body.first['id']
  end

  def test_student_cannot_get_results_for_another_students_overseer_assessment
    add_auth_header_for(user: @other_student)

    get results_url(@other_project, @assessment)

    assert_equal 404, last_response.status, last_response.body
    refute last_response.body.include?(@result.feedback_message), last_response.body
    refute last_response.body.include?("\"id\":#{@result.id}"), last_response.body
  end

  def test_student_cannot_get_results_under_a_different_task_definition
    add_auth_header_for(user: @owner)

    get results_url(@owner_project, @assessment, @other_task_definition)

    assert_equal 404, last_response.status, last_response.body
    refute last_response.body.include?(@result.feedback_message), last_response.body
    refute last_response.body.include?("\"id\":#{@result.id}"), last_response.body
  end

  def test_tutor_can_get_results_for_a_students_overseer_assessment
    add_auth_header_for(user: @tutor)

    get results_url(@owner_project, @assessment)

    assert_equal 200, last_response.status, last_response.body
    assert_equal 1, last_response_body.count, last_response.body
    assert_equal @result.id, last_response_body.first['id']
  end
end
