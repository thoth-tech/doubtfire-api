# frozen_string_literal: true

require 'test_helper'
require Rails.root.join('db/migrate/20260824000002_ensure_target_grade_changed_at_default')

class ProjectTargetGradeChangedAtTest < Minitest::Test
  def teardown
    Project.where(status: @insert_marker).delete_all if @insert_marker
    EnsureTargetGradeChangedAtDefault.new.up
    Project.reset_column_information
  end

  def test_database_default_supports_old_writers
    inserted_at = Time.current
    @insert_marker = "target-grade-default-regression-#{object_id}"

    # Bypass Project's before_create callback on purpose. This matches an older
    # application instance that does not know about target_grade_changed_at.
    # rubocop:disable Rails/SkipsModelValidations
    Project.insert_all!(
      [
        {
          status: @insert_marker,
          created_at: inserted_at,
          updated_at: inserted_at
        }
      ]
    )
    # rubocop:enable Rails/SkipsModelValidations

    project = Project.find_by!(status: @insert_marker)
    assert project.target_grade_changed_at
    assert_operator project.target_grade_changed_at, :>=, inserted_at - 1.second
  end

  def test_follow_up_migration_repairs_a_missing_default_and_is_idempotent
    migration = EnsureTargetGradeChangedAtDefault.new
    migration.change_column_default :projects, :target_grade_changed_at, nil

    assert_nil target_grade_changed_at_column.default_function

    migration.up
    assert_current_timestamp_default

    migration.up
    assert_current_timestamp_default
  end

  private

  def assert_current_timestamp_default
    value = target_grade_changed_at_column.default_function.to_s.delete(' ')
    assert_match(/\Acurrent_timestamp(?:\(\d*\))?\z/i, value)
  end

  def target_grade_changed_at_column
    ActiveRecord::Base.connection.columns(:projects).find do |column|
      column.name == 'target_grade_changed_at'
    end
  end
end
