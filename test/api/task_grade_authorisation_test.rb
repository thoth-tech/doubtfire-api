require 'test_helper'

#
# Tests that writing the grade of a task through the task update endpoint
# requires the assessment permission, and that the ordinary student
# submission path through the same endpoint is unaffected.
#
class TaskGradeAuthorisationTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper

  def app
    Rails.application
  end

  # Creates a unit with one student and a single graded task definition that
  # needs no uploaded documents.
  def create_unit_with_graded_task
    unit = FactoryBot.create(:unit, student_count: 1, task_count: 0)
    td = TaskDefinition.create!({
                                  unit_id: unit.id,
                                  tutorial_stream: unit.tutorial_streams.first,
                                  name: 'Graded task',
                                  description: 'Graded task',
                                  weighting: 4,
                                  target_grade: 0,
                                  start_date: Time.zone.now - 2.weeks,
                                  target_date: Time.zone.now + 1.week,
                                  abbreviation: 'GradedTask',
                                  restrict_status_updates: false,
                                  upload_requirements: [],
                                  plagiarism_warn_pct: 0.8,
                                  is_graded: true,
                                  max_quality_pts: 0
                                })

    [unit, td]
  end

  # The unit factory only ever employs convenors, so a tutor has to be added
  # explicitly for the tutor case to be a tutor rather than a second convenor.
  def employ_tutor(unit)
    tutor = FactoryBot.create(:user, :tutor)
    unit.employ_staff(tutor, Role.tutor)
    tutor
  end

  def test_student_cannot_set_grade_on_own_task
    unit, td = create_unit_with_graded_task
    project = unit.active_projects.first
    task = project.task_for_task_definition(td)

    add_auth_header_for(user: project.student)

    put "/api/projects/#{project.id}/task_def_id/#{td.id}", { grade: 3 }

    assert_equal 403, last_response.status, last_response_body
    assert_equal 'You are not permitted to assess this task', last_response_body['error']

    task.reload
    assert_nil task.grade

    unit.destroy
  end

  def test_tutor_can_set_grade
    unit, td = create_unit_with_graded_task
    project = unit.active_projects.first
    task = project.task_for_task_definition(td)
    tutor = employ_tutor(unit)

    assert_equal Role.tutor, tutor.role
    assert_equal :tutor, project.user_role(tutor)

    add_auth_header_for(user: tutor)

    put "/api/projects/#{project.id}/task_def_id/#{td.id}", { grade: 3 }

    assert_equal 200, last_response.status, last_response_body

    task.reload
    assert_equal 3, task.grade

    unit.destroy
  end

  def test_student_submission_without_grade_still_succeeds
    unit, td = create_unit_with_graded_task
    project = unit.active_projects.first
    task = project.task_for_task_definition(td)

    add_auth_header_for(user: project.student)

    put "/api/projects/#{project.id}/task_def_id/#{td.id}", { trigger: 'ready_for_feedback' }

    assert_equal 200, last_response.status, last_response_body

    task.reload
    assert_equal TaskStatus.ready_for_feedback, task.task_status
    assert_nil task.grade

    unit.destroy
  end

  # A refused request must not have moved the status on its way to the 403.
  def test_student_grade_with_trigger_changes_nothing
    unit, td = create_unit_with_graded_task
    project = unit.active_projects.first
    task = project.task_for_task_definition(td)
    status_before = task.task_status

    add_auth_header_for(user: project.student)

    put "/api/projects/#{project.id}/task_def_id/#{td.id}", { trigger: 'ready_for_feedback', grade: 3 }

    assert_equal 403, last_response.status, last_response_body
    assert_equal 'You are not permitted to assess this task', last_response_body['error']

    task.reload
    assert_nil task.grade
    assert_equal status_before, task.task_status
    assert_equal 0, task.task_submissions.count

    unit.destroy
  end

  def test_convenor_can_set_grade
    unit, td = create_unit_with_graded_task
    project = unit.active_projects.first
    task = project.task_for_task_definition(td)

    add_auth_header_for(user: unit.main_convenor_user)

    put "/api/projects/#{project.id}/task_def_id/#{td.id}", { grade: 2 }

    assert_equal 200, last_response.status, last_response_body

    task.reload
    assert_equal 2, task.grade

    unit.destroy
  end
end
