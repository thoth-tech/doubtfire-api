# frozen_string_literal: true

class EnsureTargetGradeChangedAtDefault < ActiveRecord::Migration[8.0]
  CURRENT_TIMESTAMP_DEFAULT = /\Acurrent_timestamp\(6\)\z/i

  def up
    column = connection.columns(:projects).find do |candidate|
      candidate.name == 'target_grade_changed_at'
    end
    raise 'projects.target_grade_changed_at must exist before its default is repaired' unless column

    return if current_timestamp_default?(column)

    change_column_default :projects,
                          :target_grade_changed_at,
                          -> { 'CURRENT_TIMESTAMP(6)' }
  end

  def down
    # The default is an ongoing rolling-deploy invariant, not temporary data
    # needed only while this migration runs. Deliberately retain it on rollback.
  end

  private

  def current_timestamp_default?(column)
    value = column.default_function || column.default
    value.to_s.delete(' ').match?(CURRENT_TIMESTAMP_DEFAULT)
  end
end
