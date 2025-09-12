class AddTutorialSelfEnrolmentToTaskDefinitions < ActiveRecord::Migration[7.1]
  def change
    unless column_exists?(:task_definitions, :tutorial_self_enrolment_enabled)
      add_column :task_definitions, :tutorial_self_enrolment_enabled, :boolean, default: false, null: false
      add_index :task_definitions, :tutorial_self_enrolment_enabled
    end

    unless column_exists?(:task_definitions, :tutorial_self_enrolment_stream_id)
      add_reference :task_definitions, :tutorial_self_enrolment_stream, foreign_key: { to_table: :tutorial_streams }, null: true
      add_index :task_definitions, :tutorial_self_enrolment_stream_id
    end
  end
end
