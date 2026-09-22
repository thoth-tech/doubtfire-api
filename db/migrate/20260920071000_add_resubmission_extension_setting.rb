class AddResubmissionExtensionSetting < ActiveRecord::Migration[8.0]
  def change
    add_column :task_definitions, :resubmission_extensions_enabled, :boolean, default: true, null: false
    add_column :task_definitions, :resubmission_extensions_changed_at, :datetime
    add_reference :task_definitions, :resubmission_extensions_changed_by,
                  foreign_key: { to_table: :users, on_delete: :nullify }
  end
end
