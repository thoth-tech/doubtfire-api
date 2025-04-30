class AddPrerequisiteToUnits < ActiveRecord::Migration[7.1]
  def change
    add_column :units, :prerequisite, :string
  end
end
