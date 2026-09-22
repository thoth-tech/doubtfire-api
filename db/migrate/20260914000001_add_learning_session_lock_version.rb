# frozen_string_literal: true

class AddLearningSessionLockVersion < ActiveRecord::Migration[8.0]
  def change
    add_column :unit_learning_sessions, :lock_version, :integer, null: false, default: 0
  end
end
