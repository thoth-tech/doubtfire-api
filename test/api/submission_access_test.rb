# frozen_string_literal: true

require 'test_helper'

# Access-control regression coverage for the submission_details and
# submission_files endpoints in tasks_api.rb. Neither endpoint currently
# has any dedicated test coverage on main, despite both serving another
# student's submission data/files behind a single `authorise?` check.
#
# These tests do not change any application behaviour - they only assert
# that the existing `authorise? current_user, project, :get_submission`
# guard actually blocks the object-reference paths it's meant to.
class SubmissionAccessTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper

  def app
    Rails.application
  end

  def setup
    @unit = FactoryBot.create(:unit, perform_submissions: true, student_count: 3, staff_count: 1)
    @task_definition = @unit.task_definitions.first
    @owning_project = @unit.projects.first
    @other_project = @unit.projects.second

    @convenor = @unit.main_convenor_user
    @tutor = FactoryBot.create(:user, :tutor)
    @unit.employ_staff(@tutor, Role.tutor)

    @other_unit = FactoryBot.create(:unit, student_count: 1, staff_count: 1)
    @other_unit_task_definition = @other_unit.task_definitions.first
  end

  def details_endpoint(project: @owning_project, task_definition: @task_definition)
    "/api/projects/#{project.id}/task_def_id/#{task_definition.id}/submission_details"
  end

  def files_endpoint(project: @owning_project, task_definition: @task_definition)
    "/api/projects/#{project.id}/task_def_id/#{task_definition.id}/submission_files"
  end

  # ---------------------------------------------------------------------
  # submission_details
  # ---------------------------------------------------------------------

  def test_submission_details_allows_owning_student
    add_auth_header_for(user: @owning_project.student)

    get details_endpoint

    assert_equal 200, last_response.status
    assert last_response_body.key?('has_pdf')
    assert last_response_body.key?('processing_pdf')
  end

  # A student is not a unit_role, so the claimed_by_unit_role_id key
  # (staff-only data about who has claimed the overflow task) should not
  # appear in their response at all.
  def test_submission_details_does_not_expose_claim_info_to_student
    add_auth_header_for(user: @owning_project.student)

    get details_endpoint

    assert_equal 200, last_response.status
    refute last_response_body.key?('claimed_by_unit_role_id')
  end

  def test_submission_details_allows_unit_convenor
    add_auth_header_for(user: @convenor)

    get details_endpoint

    assert_equal 200, last_response.status
  end

  # Staff (anyone with a unit_role) should see the claim-tracking field,
  # even if it is null (no overflow claim exists yet).
  def test_submission_details_exposes_claim_info_to_convenor
    add_auth_header_for(user: @convenor)

    get details_endpoint

    assert_equal 200, last_response.status
    assert last_response_body.key?('claimed_by_unit_role_id')
  end

  def test_submission_details_allows_unit_tutor
    add_auth_header_for(user: @tutor)

    get details_endpoint

    assert_equal 200, last_response.status
  end

  def test_submission_details_blocks_other_student_in_same_unit
    add_auth_header_for(user: @other_project.student)

    get details_endpoint(project: @owning_project)

    assert_equal 403, last_response.status
    assert_equal 'You do not have permission to read submissions for this project.',
                 last_response_body['error']
  end

  def test_submission_details_blocks_staff_from_a_different_unit
    other_unit_staff = @other_unit.main_convenor_user
    add_auth_header_for(user: other_unit_staff)

    get details_endpoint(project: @owning_project)

    assert_equal 403, last_response.status
  end

  def test_submission_details_blocks_unauthenticated_request
    header 'auth_token', nil
    header 'username', nil

    get details_endpoint

    assert_equal 419, last_response.status
  end

  def test_submission_details_rejects_task_definition_from_another_unit
    add_auth_header_for(user: @owning_project.student)

    get details_endpoint(task_definition: @other_unit_task_definition)

    assert_equal 404, last_response.status
  end

  # ---------------------------------------------------------------------
  # submission_files
  # ---------------------------------------------------------------------

  def test_submission_files_allows_owning_student
    add_auth_header_for(user: @owning_project.student)

    get files_endpoint

    assert_equal 200, last_response.status
  end

  def test_submission_files_blocks_other_student_in_same_unit
    add_auth_header_for(user: @other_project.student)

    get files_endpoint(project: @owning_project)

    assert_equal 403, last_response.status
  end

  def test_submission_files_blocks_staff_from_a_different_unit
    other_unit_staff = @other_unit.main_convenor_user
    add_auth_header_for(user: other_unit_staff)

    get files_endpoint(project: @owning_project)

    assert_equal 403, last_response.status
  end

  # Regression guard: the Content-Disposition filename is built from
  # project.student.username. Confirm that only ever happens for a caller
  # who has already passed the authorise? check - i.e. a cross-student
  # request never reaches the point where the filename (and therefore the
  # other student's username) is constructed or exposed in the response.
  def test_submission_files_does_not_leak_owning_students_username_to_blocked_caller
    add_auth_header_for(user: @other_project.student)

    get files_endpoint(project: @owning_project)

    assert_equal 403, last_response.status
    refute_match(/#{@owning_project.student.username}/, last_response.headers['Content-Disposition'].to_s)
  end

  def test_submission_files_blocks_unauthenticated_request
    header 'auth_token', nil
    header 'username', nil

    get files_endpoint

    assert_equal 419, last_response.status
  end
end