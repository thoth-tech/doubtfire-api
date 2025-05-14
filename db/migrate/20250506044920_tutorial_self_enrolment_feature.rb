class TutorialSelfEnrolmentFeature < ActiveRecord::Migration[7.1]
  def change
    add_column :task_definitions, :tutorial_self_enrolment_enabled, :boolean, default: false
    add_reference :task_definitions, :tutorial_self_enrolment_stream, foreign_key: { to_table: :tutorial_streams }
  end
end
