class AddTutorialSelfEnrolmentToTaskDefinitions < ActiveRecord::Migration[7.1]
  def change
    add_column :task_definitions, :tutorial_self_enrolment_enabled, :boolean, default: false, null: false
    add_reference :task_definitions, :tutorial_self_enrolment_stream, foreign_key: { to_table: :tutorial_streams }, null: true

    # Add index for better query performance
    add_index :task_definitions, :tutorial_self_enrolment_enabled
    add_index :task_definitions, :tutorial_self_enrolment_stream_id
  end

  def down
    remove_index :task_definitions, :tutorial_self_enrolment_enabled
    remove_index :task_definitions, :tutorial_self_enrolment_stream_id
    remove_reference :task_definitions, :tutorial_self_enrolment_stream
    remove_column :task_definitions, :tutorial_self_enrolment_enabled
  end
end
