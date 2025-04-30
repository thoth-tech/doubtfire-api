class AddCreditPointsToUnits < ActiveRecord::Migration[7.1]
  def change
    add_column :units, :creditpoint, :integer
  end
end
