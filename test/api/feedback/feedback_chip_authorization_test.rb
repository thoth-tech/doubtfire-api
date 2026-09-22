require 'test_helper'

class FeedbackChipAuthorizationTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper

  def app
    Rails.application
  end

  def global_chip
    outcome = FactoryBot.create(:learning_outcome, context_type: nil, context_id: nil)
    FactoryBot.create(:feedback_template_chip, learning_outcome_id: outcome.id)
  end

  def track_usage(chip, params = {})
    post "api/feedback_template_chip/#{chip.id}/track_usage", params
  end

  def test_student_cannot_track_feedback_chip_usage
    chip = global_chip
    student = FactoryBot.create(:user, :student, enrol_in: 1)

    add_auth_header_for user: student
    track_usage chip

    assert_equal 403, last_response.status,
      "Expected 403 Forbidden - a student should not be able to track feedback chip usage."
    assert_equal 0, chip.chip_usages.count
  end

  def test_auditor_cannot_track_feedback_chip_usage
    chip = global_chip
    auditor = FactoryBot.create(:user, :auditor)

    add_auth_header_for user: auditor
    track_usage chip

    assert_equal 403, last_response.status
    assert_equal 0, chip.chip_usages.count
  end

  # tutor_id is no longer read, so a caller who is refused gets the same answer
  # whether it names a real user or not, and cannot use it to find user ids.
  def test_refused_caller_cannot_tell_which_user_ids_exist
    chip = global_chip
    student = FactoryBot.create(:user, :student, enrol_in: 1)
    existing_user = FactoryBot.create(:user, :tutor)
    missing_user_id = User.maximum(:id) + 1000

    add_auth_header_for user: student

    track_usage chip, tutor_id: existing_user.id
    existing_user_response = [last_response.status, last_response.body]

    track_usage chip, tutor_id: missing_user_id
    missing_user_response = [last_response.status, last_response.body]

    assert_equal 403, existing_user_response.first
    assert_equal existing_user_response, missing_user_response
  end

  def test_tutor_can_track_feedback_chip_usage
    chip = global_chip
    marking_tutor = FactoryBot.create(:user, :tutor)

    add_auth_header_for user: marking_tutor
    track_usage chip

    assert_equal 201, last_response.status,
      "Expected 201 Created - a tutor should be able to track feedback chip usage. " \
      "Response: #{last_response.body}"

    usage = Feedback::ChipUsage.find_by(feedback_chip: chip, tutor: marking_tutor)
    assert_not_nil usage, "Expected a ChipUsage record for the tutor who made the request"
    assert_equal 1, usage.usage_count
  end

  def test_usage_is_recorded_against_the_caller_not_a_requested_tutor
    chip = global_chip
    marking_tutor = FactoryBot.create(:user, :tutor)
    other_user = FactoryBot.create(:user, :student)

    add_auth_header_for user: marking_tutor
    track_usage chip, tutor_id: other_user.id

    assert_equal 201, last_response.status
    assert_equal [marking_tutor.id], chip.chip_usages.pluck(:tutor_id)
  end

  def test_repeated_use_increments_the_callers_count
    chip = global_chip
    marking_tutor = FactoryBot.create(:user, :tutor)

    add_auth_header_for user: marking_tutor
    2.times { track_usage chip }

    assert_equal 201, last_response.status
    assert_equal 1, chip.chip_usages.count
    assert_equal 2, chip.chip_usages.find_by(tutor: marking_tutor).usage_count
  end

  # On a global chip a convenor is treated as a tutor, so use a unit chip to
  # reach the convenor permission.
  def test_convenor_can_track_feedback_chip_usage
    unit = FactoryBot.create(:unit, with_students: false)
    chip = FactoryBot.create(:feedback_template_chip, learning_outcome_id: unit.learning_outcomes.first.id)
    convenor = FactoryBot.create(:user, :convenor)
    unit.employ_staff(convenor, Role.convenor)

    add_auth_header_for user: convenor
    track_usage chip

    assert_equal 201, last_response.status
    assert_equal [convenor.id], chip.chip_usages.pluck(:tutor_id)
  end

  def test_admin_can_track_feedback_chip_usage
    chip = global_chip
    admin = FactoryBot.create(:user, :admin)

    add_auth_header_for user: admin
    track_usage chip

    assert_equal 201, last_response.status
    assert_equal [admin.id], chip.chip_usages.pluck(:tutor_id)
  end

  def test_only_staff_in_the_unit_can_track_its_chips
    unit = FactoryBot.create(:unit, with_students: false)
    chip = FactoryBot.create(:feedback_template_chip, learning_outcome_id: unit.learning_outcomes.first.id)
    unit_tutor = FactoryBot.create(:user, :tutor)
    unit.employ_staff(unit_tutor, Role.tutor)
    tutor_from_another_unit = FactoryBot.create(:user, :tutor)

    add_auth_header_for user: tutor_from_another_unit
    track_usage chip

    assert_equal 403, last_response.status

    add_auth_header_for user: unit_tutor
    track_usage chip

    assert_equal 201, last_response.status
    assert_equal [unit_tutor.id], chip.chip_usages.pluck(:tutor_id)
  end

  def test_observer_only_staff_cannot_track_unit_chip_usage
    unit = FactoryBot.create(:unit, with_students: false)
    chip = FactoryBot.create(:feedback_template_chip, learning_outcome_id: unit.learning_outcomes.first.id)
    observer = FactoryBot.create(:user, :tutor)
    unit.employ_staff(observer, Role.tutor)
    unit.unit_role_for(observer).update!(observer_only: true)

    add_auth_header_for user: observer
    track_usage chip

    assert_equal 403, last_response.status
    assert_equal 0, chip.chip_usages.count
  end

  def test_observer_only_staff_cannot_track_task_chip_usage
    unit = FactoryBot.create(:unit, with_students: false)
    task_outcome = FactoryBot.create(:learning_outcome, context_type: 'TaskDefinition', context_id: unit.task_definitions.first.id)
    chip = FactoryBot.create(:feedback_template_chip, learning_outcome_id: task_outcome.id)
    observer = FactoryBot.create(:user, :tutor)
    unit.employ_staff(observer, Role.tutor)
    unit.unit_role_for(observer).update!(observer_only: true)

    add_auth_header_for user: observer
    track_usage chip

    assert_equal 403, last_response.status
    assert_equal 0, chip.chip_usages.count
  end
end
