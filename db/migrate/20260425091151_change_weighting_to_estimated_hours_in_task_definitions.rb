class ChangeWeightingToEstimatedHoursInTaskDefinitions < ActiveRecord::Migration[8.0]
  def change
    rename_column :task_definitions, :weighting, :estimated_hours
  end
end
