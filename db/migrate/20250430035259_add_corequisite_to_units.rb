class AddCorequisiteToUnits < ActiveRecord::Migration[7.1]
  def change
    add_column :units, :corequisite, :string
  end
end
