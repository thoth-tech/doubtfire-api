class AddEstimatedTimeMinutesToTaskDefinitions < ActiveRecord::Migration[7.1]
  def up
    add_column :task_definitions, :estimated_time_minutes, :integer, null: true, default: 0, comment: "Estimated time to complete task, measured in minutes"
  end

  def down
    remove_column :task_definitions, :estimated_time_minutes
  end
end
