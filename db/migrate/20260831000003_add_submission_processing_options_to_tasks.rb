class AddSubmissionProcessingOptionsToTasks < ActiveRecord::Migration[8.0]
  # Kept separate from 20260831000002 because an environment built from #123
  # (for example through deploy#34's API pin) may already have run that one.
  def change
    add_column :tasks, :submission_processing_mode, :string
    add_column :tasks, :submission_processing_user_id, :bigint
    add_column :tasks, :submission_processing_test_submission, :boolean, default: false, null: false
    add_column :tasks, :submission_processing_accepted_tii_eula, :boolean, default: false, null: false
  end
end
