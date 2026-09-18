class AddSubmissionProcessingStateToTasks < ActiveRecord::Migration[8.0]
  def change
    add_column :tasks, :submission_processing_state, :string
    add_column :tasks, :submission_processing_started_at, :datetime
    add_column :tasks, :submission_processing_finished_at, :datetime
    add_column :tasks, :submission_processing_error_code, :string
    add_column :tasks, :submission_processing_attempts, :integer, default: 0, null: false
  end
end
