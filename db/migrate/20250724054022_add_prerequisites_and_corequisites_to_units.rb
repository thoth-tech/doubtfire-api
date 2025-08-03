class AddPrerequisitesAndCorequisitesToUnits < ActiveRecord::Migration[7.1]
  def change
    add_column :units, :prerequisites, :text
    add_column :units, :corequisites, :text
  end
end
