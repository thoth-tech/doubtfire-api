class AddPredictionEnabledFlagToUnits < ActiveRecord::Migration[8.0]
  def change
    add_column :units, :allow_effort_predictions, :boolean, null: false, default: false
  end
end
