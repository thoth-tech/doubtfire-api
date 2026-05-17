class SetDefaultPredictedEffortOnTaskDefinitions < ActiveRecord::Migration[8.0]
  def up
    change_column_default :task_definitions, :predicted_effort, 1.0
    TaskDefinition.where(predicted_effort: nil).update_all(predicted_effort: 1.0)
  end

  def down
    change_column_default :task_definitions, :predicted_effort, nil
  end
end
