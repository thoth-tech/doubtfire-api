require 'test_helper'

class TestAttemptsTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper

  def app
    Rails.application
  end

  def test_get_task_attempts
    unit = FactoryBot.create(:unit)
    project = unit.projects.first
    user = project.student

    td = TaskDefinition.new(
      {
        unit_id: unit.id,
        tutorial_stream: unit.tutorial_streams.first,
        name: 'Test attempts',
        description: 'Test attempts',
        weighting: 4,
        target_grade: 0,
        start_date: Time.zone.now - 2.weeks,
        target_date: Time.zone.now - 1.week,
        due_date: Time.zone.now + 1.week,
        abbreviation: 'TestAttempts',
        restrict_status_updates: false,
        upload_requirements: [],
        plagiarism_warn_pct: 0.8,
        is_graded: false,
        max_quality_pts: 0,
        scorm_enabled: true,
        scorm_attempt_limit: 0
      }
    )
    td.save!

    add_auth_header_for(user: user)

    # When no attempts exist
    get "api/projects/#{project.id}/task_def_id/#{td.id}/test_attempts"
    assert_equal 200, last_response.status
    assert_empty last_response_body

    task = project.task_for_task_definition(td)
    attempt = TestAttempt.create({ task_id: task.id })

    td1 = TaskDefinition.new(
      {
        unit_id: unit.id,
        tutorial_stream: unit.tutorial_streams.first,
        name: 'Test attempts new',
        description: 'Test attempts new',
        weighting: 4,
        target_grade: 0,
        start_date: Time.zone.now - 2.weeks,
        target_date: Time.zone.now - 1.week,
        due_date: Time.zone.now + 1.week,
        abbreviation: 'TestAttemptsNew',
        restrict_status_updates: false,
        upload_requirements: [],
        plagiarism_warn_pct: 0.8,
        is_graded: false,
        max_quality_pts: 0,
        scorm_enabled: true,
        scorm_attempt_limit: 0
      }
    )
    td1.save!

    task1 = project.task_for_task_definition(td1)
    attempt1 = TestAttempt.create({ task_id: task1.id })

    add_auth_header_for(user: user)

    response_keys = %w[id task_id terminated completion_status success_status score_scaled cmi_datamodel]

    # When attempts exists
    get "api/projects/#{project.id}/task_def_id/#{td.id}/test_attempts"
    assert_equal 200, last_response.status
    assert_equal 1, last_response_body.size
    assert_json_matches_model attempt, last_response_body.first, response_keys

    user1 = FactoryBot.create(:user, :student)

    add_auth_header_for(user: user1)

    # When user is unauthorised
    get "api/projects/#{project.id}/task_def_id/#{td.id}/test_attempts"
    assert_equal 403, last_response.status

    user1.destroy!
    td.destroy!
    td1.destroy!
    unit.destroy!
  end

  def test_get_latest
    unit = FactoryBot.create(:unit)
    project = unit.projects.first
    user = project.student

    td = TaskDefinition.new(
      {
        unit_id: unit.id,
        tutorial_stream: unit.tutorial_streams.first,
        name: 'Test attempts',
        description: 'Test attempts',
        weighting: 4,
        target_grade: 0,
        start_date: Time.zone.now - 2.weeks,
        target_date: Time.zone.now - 1.week,
        due_date: Time.zone.now + 1.week,
        abbreviation: 'TestAttempts',
        restrict_status_updates: false,
        upload_requirements: [],
        plagiarism_warn_pct: 0.8,
        is_graded: false,
        max_quality_pts: 0,
        scorm_enabled: true,
        scorm_attempt_limit: 0
      }
    )
    td.save!

    add_auth_header_for(user: user)

    # When no attempts exist
    get "api/projects/#{project.id}/task_def_id/#{td.id}/test_attempts/latest"
    assert_equal 404, last_response.status

    task = project.task_for_task_definition(td)
    attempt = TestAttempt.create({ task_id: task.id })
    attempt.terminated = true
    attempt.completion_status = true
    attempt.save!
    attempt1 = TestAttempt.create({ task_id: task.id })

    add_auth_header_for(user: user)

    response_keys = %w[id task_id terminated completion_status success_status score_scaled cmi_datamodel]

    # When attempts exist
    get "api/projects/#{project.id}/task_def_id/#{td.id}/test_attempts/latest"
    assert_equal 200, last_response.status
    assert_json_matches_model attempt1, last_response_body, response_keys

    add_auth_header_for(user: user)

    # Get completed latest
    get "api/projects/#{project.id}/task_def_id/#{td.id}/test_attempts/latest?completed=true"
    assert_equal 200, last_response.status
    assert_json_matches_model attempt, last_response_body, response_keys

    user1 = FactoryBot.create(:user, :student)

    add_auth_header_for(user: user1)

    # When user is unauthorised
    get "api/projects/#{project.id}/task_def_id/#{td.id}/test_attempts/latest"
    assert_equal 403, last_response.status

    td.destroy!
    unit.destroy!
  end

  def test_review_attempt
    unit = FactoryBot.create(:unit)
    project = unit.projects.first
    user = project.student

    td = TaskDefinition.new(
      {
        unit_id: unit.id,
        tutorial_stream: unit.tutorial_streams.first,
        name: 'Test attempts',
        description: 'Test attempts',
        weighting: 4,
        target_grade: 0,
        start_date: Time.zone.now - 2.weeks,
        target_date: Time.zone.now - 1.week,
        due_date: Time.zone.now + 1.week,
        abbreviation: 'TestAttempts',
        restrict_status_updates: false,
        upload_requirements: [],
        plagiarism_warn_pct: 0.8,
        is_graded: false,
        max_quality_pts: 0,
        scorm_enabled: true,
        scorm_attempt_limit: 0,
        scorm_allow_review: true
      }
    )
    td.save!

    add_auth_header_for(user: user)

    # When attempt id is invalid
    get "api/test_attempts/0/review"
    assert_equal 404, last_response.status

    task = project.task_for_task_definition(td)
    attempt = TestAttempt.create({ task_id: task.id })

    td.scorm_allow_review = false
    td.save!

    add_auth_header_for(user: user)

    # When review is disabled
    get "api/test_attempts/#{attempt.id}/review"
    assert_equal 403, last_response.status

    td.scorm_allow_review = true
    td.save!

    add_auth_header_for(user: user)

    # When attempt is incomplete
    get "api/test_attempts/#{attempt.id}/review"
    assert_equal 403, last_response.status

    dm = JSON.parse(attempt.cmi_datamodel)
    dm['cmi.completion_status'] = 'completed'
    attempt.cmi_datamodel = dm.to_json
    attempt.completion_status = true
    attempt.terminated = true
    attempt.save!

    add_auth_header_for(user: user)

    # When attempt can be reviewed
    get "api/test_attempts/#{attempt.id}/review"
    assert_equal 200, last_response.status

    attempt.review
    attempt.save!

    response_keys = %w[id task_id terminated completion_status success_status score_scaled cmi_datamodel]
    assert_json_matches_model attempt, last_response_body, response_keys

    tutor = project.tutor_for(td)

    add_auth_header_for(user: tutor)

    # When user is tutor
    get "api/test_attempts/#{attempt.id}/review"
    assert_equal 200, last_response.status
    assert_json_matches_model attempt, last_response_body, response_keys

    user1 = FactoryBot.create(:user, :student)

    add_auth_header_for(user: user1)

    # When user is unauthorised
    get "api/test_attempts/#{attempt.id}/review"
    assert_equal 403, last_response.status

    td.destroy!
    unit.destroy!
  end

  def test_post_attempt
    unit = FactoryBot.create(:unit)
    project = unit.projects.first
    user = project.student

    td = TaskDefinition.new(
      {
        unit_id: unit.id,
        tutorial_stream: unit.tutorial_streams.first,
        name: 'Test attempts',
        description: 'Test attempts',
        weighting: 4,
        target_grade: 0,
        start_date: Time.zone.now - 2.weeks,
        target_date: Time.zone.now - 1.week,
        due_date: Time.zone.now + 1.week,
        abbreviation: 'TestAttempts',
        restrict_status_updates: false,
        upload_requirements: [],
        plagiarism_warn_pct: 0.8,
        is_graded: false,
        max_quality_pts: 0,
        scorm_enabled: false,
        scorm_attempt_limit: 1
      }
    )
    td.save!

    add_auth_header_for(user: user)

    # When scorm is disabled
    post "api/projects/#{project.id}/task_def_id/#{td.id}/test_attempts"
    assert_equal 403, last_response.status

    td.scorm_enabled = true
    td.save!

    tutor = project.tutor_for(td)

    add_auth_header_for(user: tutor)

    # When user is unauthorised
    post "api/projects/#{project.id}/task_def_id/#{td.id}/test_attempts"
    assert_equal 403, last_response.status

    task = project.task_for_task_definition(td)

    add_auth_header_for(user: user)

    # When new attempt can be made
    post "api/projects/#{project.id}/task_def_id/#{td.id}/test_attempts"
    assert_equal 201, last_response.status
    assert last_response_body["task_id"] == task.id

    attempt = TestAttempt.find(last_response_body["id"])

    add_auth_header_for(user: user)

    # When last attempt is incomplete
    post "api/projects/#{project.id}/task_def_id/#{td.id}/test_attempts"
    assert_equal 400, last_response.status

    attempt.terminated = true
    attempt.success_status = true
    attempt.save!

    add_auth_header_for(user: user)

    # When last attempt is a pass
    post "api/projects/#{project.id}/task_def_id/#{td.id}/test_attempts"
    assert_equal 400, last_response.status

    attempt.success_status = false
    attempt.save!

    add_auth_header_for(user: user)

    # When attempt limit is reached
    post "api/projects/#{project.id}/task_def_id/#{td.id}/test_attempts"
    assert_equal 400, last_response.status

    td.destroy!
    unit.destroy!
  end

  def test_update_attempt
    unit = FactoryBot.create(:unit)
    project = unit.projects.first
    user = project.student

    td = TaskDefinition.new(
      {
        unit_id: unit.id,
        tutorial_stream: unit.tutorial_streams.first,
        name: 'Test attempts',
        description: 'Test attempts',
        weighting: 4,
        target_grade: 0,
        start_date: Time.zone.now - 2.weeks,
        target_date: Time.zone.now - 1.week,
        due_date: Time.zone.now + 1.week,
        abbreviation: 'TestAttempts',
        restrict_status_updates: false,
        upload_requirements: [],
        plagiarism_warn_pct: 0.8,
        is_graded: false,
        max_quality_pts: 0,
        scorm_enabled: true,
        scorm_attempt_limit: 0
      }
    )
    td.save!

    tutor = project.tutor_for(td)

    task = project.task_for_task_definition(td)
    attempt = TestAttempt.create({ task_id: task.id })

    dm = JSON.parse(attempt.cmi_datamodel)
    dm["cmi.completion_status"] = "completed"
    dm["cmi.score.scaled"] = "0.1"

    data_to_patch = {
      cmi_datamodel: dm.to_json,
      terminated: true
    }

    add_auth_header_for(user: tutor)

    # When user is unauthorised
    patch "api/test_attempts/#{attempt.id}", data_to_patch
    assert_equal 403, last_response.status

    add_auth_header_for(user: user)

    # When attempt is terminated
    patch "api/test_attempts/#{attempt.id}", data_to_patch
    assert_equal 200, last_response.status

    attempt = TestAttempt.find(attempt.id)

    assert attempt.terminated == true
    assert JSON.parse(attempt.cmi_datamodel)["cmi.completion_status"] == "completed"

    tc = ScormComment.find_by(commentable_id: attempt.id)

    assert_not_nil tc

    add_auth_header_for(user: user)

    # When unauthorised user tries to override pass status
    patch "api/test_attempts/#{attempt.id}", { success_status: true }
    assert_equal 403, last_response.status

    add_auth_header_for(user: tutor)

    # When authorised user tries to override pass status
    patch "api/test_attempts/#{attempt.id}", { success_status: true }
    assert_equal 200, last_response.status

    attempt = TestAttempt.find(attempt.id)

    assert attempt.success_status == true
    assert JSON.parse(attempt.cmi_datamodel)["cmi.success_status"] == "passed"

    tc = ScormComment.find_by(commentable_id: attempt.id)

    assert tc.comment == attempt.success_status_description

    add_auth_header_for(user: tutor)

    # When attempt id is invalid
    patch "api/test_attempts/0", { success_status: true }
    assert_equal 404, last_response.status

    td.destroy!
    unit.destroy!
  end

  def test_delete_attempt
    unit = FactoryBot.create(:unit)
    project = unit.projects.first
    user = project.student

    td = TaskDefinition.new(
      {
        unit_id: unit.id,
        tutorial_stream: unit.tutorial_streams.first,
        name: 'Test attempts',
        description: 'Test attempts',
        weighting: 4,
        target_grade: 0,
        start_date: Time.zone.now - 2.weeks,
        target_date: Time.zone.now - 1.week,
        due_date: Time.zone.now + 1.week,
        abbreviation: 'TestAttempts',
        restrict_status_updates: false,
        upload_requirements: [],
        plagiarism_warn_pct: 0.8,
        is_graded: false,
        max_quality_pts: 0,
        scorm_enabled: true,
        scorm_attempt_limit: 0
      }
    )
    td.save!

    task = project.task_for_task_definition(td)
    attempt = TestAttempt.create({ task_id: task.id })

    add_auth_header_for(user: user)

    # When user is unauthorised
    delete "api/test_attempts/#{attempt.id}"
    assert_equal 403, last_response.status

    tutor = project.tutor_for(td)

    add_auth_header_for(user: tutor)

    # When user is authorised
    delete "api/test_attempts/#{attempt.id}"
    assert_equal 200, last_response.status

    add_auth_header_for(user: tutor)

    # When attempt id is invalid
    delete "api/test_attempts/0"
    assert_equal 404, last_response.status

    td.destroy!
    unit.destroy!
  end

  # A student may write their own scorm runtime state, but the pass or fail
  # decision belongs to staff. Sending it inside the datamodel must not move it.
  def test_student_cannot_pass_own_attempt_via_datamodel
    unit = FactoryBot.create(:unit)
    project = unit.projects.first
    user = project.student
    td = scorm_task_definition(unit, 'ScormPassInjection')

    task = project.task_for_task_definition(td)
    attempt = TestAttempt.create({ task_id: task.id })

    dm = JSON.parse(attempt.cmi_datamodel)
    dm["cmi.completion_status"] = "completed"
    dm["cmi.success_status"] = "passed"
    dm["cmi.score.scaled"] = "1"

    add_auth_header_for(user: user)

    patch "api/test_attempts/#{attempt.id}", { cmi_datamodel: dm.to_json }
    assert_equal 200, last_response.status

    attempt = TestAttempt.find(attempt.id)

    # Completion is the student's own progress, so it still lands.
    assert_equal true, attempt.completion_status
    # The pass and the score are not, so both columns keep their defaults. The
    # score is pinned to 0.0 rather than "not 1.0" so a partial score leaking
    # through would fail here too.
    assert_equal false, attempt.success_status
    assert_equal 0.0, attempt.score_scaled

    td.destroy!
    unit.destroy!
  end

  # The ordinary case. Completion, resume and the interactions counter are the
  # student's to write and none of them are affected by the change above.
  def test_student_can_record_ordinary_progress_and_resume
    unit = FactoryBot.create(:unit)
    project = unit.projects.first
    user = project.student
    td = scorm_task_definition(unit, 'ScormProgress')

    task = project.task_for_task_definition(td)
    attempt = TestAttempt.create({ task_id: task.id })

    dm = JSON.parse(attempt.cmi_datamodel)
    dm["cmi.completion_status"] = "incomplete"
    dm["cmi.interactions._count"] = "3"

    add_auth_header_for(user: user)

    patch "api/test_attempts/#{attempt.id}", { cmi_datamodel: dm.to_json }
    assert_equal 200, last_response.status

    attempt = TestAttempt.find(attempt.id)
    saved = JSON.parse(attempt.cmi_datamodel)

    assert_equal "resume", saved["cmi.entry"]
    assert_equal "3", saved["cmi.interactions._count"]
    assert_equal false, attempt.completion_status
    assert_equal false, attempt.terminated

    saved["cmi.completion_status"] = "completed"

    add_auth_header_for(user: user)

    patch "api/test_attempts/#{attempt.id}", { cmi_datamodel: saved.to_json, terminated: true }
    assert_equal 200, last_response.status

    attempt = TestAttempt.find(attempt.id)

    assert_equal true, attempt.completion_status
    assert_equal true, attempt.terminated

    td.destroy!
    unit.destroy!
  end

  # The staff path is untouched. It writes success_status directly and never
  # goes through the datamodel setter.
  def test_tutor_can_still_override_success_status
    unit = FactoryBot.create(:unit)
    project = unit.projects.first
    user = project.student
    td = scorm_task_definition(unit, 'ScormTutorOverride')
    tutor = project.tutor_for(td)

    task = project.task_for_task_definition(td)
    attempt = TestAttempt.create({ task_id: task.id })

    dm = JSON.parse(attempt.cmi_datamodel)
    dm["cmi.completion_status"] = "completed"

    add_auth_header_for(user: user)

    patch "api/test_attempts/#{attempt.id}", { cmi_datamodel: dm.to_json, terminated: true }
    assert_equal 200, last_response.status

    add_auth_header_for(user: tutor)

    patch "api/test_attempts/#{attempt.id}", { success_status: true }
    assert_equal 200, last_response.status

    attempt = TestAttempt.find(attempt.id)

    assert_equal true, attempt.success_status
    assert_equal "passed", JSON.parse(attempt.cmi_datamodel)["cmi.success_status"]

    td.destroy!
    unit.destroy!
  end

  # The check that was already there on the route still stands.
  def test_student_cannot_send_success_status_directly
    unit = FactoryBot.create(:unit)
    project = unit.projects.first
    user = project.student
    td = scorm_task_definition(unit, 'ScormDirectOverride')

    task = project.task_for_task_definition(td)
    attempt = TestAttempt.create({ task_id: task.id })

    add_auth_header_for(user: user)

    patch "api/test_attempts/#{attempt.id}", { success_status: true }
    assert_equal 403, last_response.status

    attempt = TestAttempt.find(attempt.id)

    assert_equal false, attempt.success_status

    td.destroy!
    unit.destroy!
  end

  # The other half of the change, written down so it is not read later as a
  # regression. A student whose package genuinely reports a pass no longer has
  # that pass recorded. The attempt reads as unsuccessful, and because nothing
  # reads it as a pass the student is not blocked from trying again. Staff
  # recording it is the only path to a pass.
  def test_legitimate_pass_is_only_recorded_by_staff
    unit = FactoryBot.create(:unit)
    project = unit.projects.first
    user = project.student
    td = scorm_task_definition(unit, 'ScormLegitimatePass')
    tutor = project.tutor_for(td)

    task = project.task_for_task_definition(td)
    attempt = TestAttempt.create({ task_id: task.id })

    dm = JSON.parse(attempt.cmi_datamodel)
    dm["cmi.completion_status"] = "completed"
    dm["cmi.success_status"] = "passed"
    dm["cmi.score.scaled"] = "1"

    add_auth_header_for(user: user)

    patch "api/test_attempts/#{attempt.id}", { cmi_datamodel: dm.to_json, terminated: true }
    assert_equal 200, last_response.status

    attempt = TestAttempt.find(attempt.id)

    assert_equal true, attempt.completion_status
    assert_equal false, attempt.success_status
    assert_equal 0.0, attempt.score_scaled

    # The comment both the student and the tutor read on the task.
    assert_equal "Unsuccessful", attempt.scorm_comment.comment

    # The attempt gate reads success_status, so it does not close on the student.
    add_auth_header_for(user: user)

    post "api/projects/#{project.id}/task_def_id/#{td.id}/test_attempts"
    assert_equal 201, last_response.status

    # And the staff override is still the way the pass gets recorded.
    add_auth_header_for(user: tutor)

    patch "api/test_attempts/#{attempt.id}", { success_status: true }
    assert_equal 200, last_response.status

    assert_equal true, TestAttempt.find(attempt.id).success_status

    td.destroy!
    unit.destroy!
  end

  # A scorm enabled task definition, with the settings the other tests in this
  # file already use. Not marked private, because a private keyword here would
  # silently stop minitest collecting any test method appended below it.
  def scorm_task_definition(unit, abbreviation)
    td = TaskDefinition.new(
      {
        unit_id: unit.id,
        tutorial_stream: unit.tutorial_streams.first,
        name: "Test attempts #{abbreviation}",
        description: 'Test attempts',
        weighting: 4,
        target_grade: 0,
        start_date: Time.zone.now - 2.weeks,
        target_date: Time.zone.now - 1.week,
        due_date: Time.zone.now + 1.week,
        abbreviation: abbreviation,
        restrict_status_updates: false,
        upload_requirements: [],
        plagiarism_warn_pct: 0.8,
        is_graded: false,
        max_quality_pts: 0,
        scorm_enabled: true,
        scorm_attempt_limit: 0
      }
    )
    td.save!
    td
  end
end
