class AddPredictedEffortToTasks < ActiveRecord::Migration[8.0]
  def change
    add_column :task_definitions, :predicted_effort, :float
  end
end
