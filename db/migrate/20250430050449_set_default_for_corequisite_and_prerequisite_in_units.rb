class SetDefaultForCorequisiteAndPrerequisiteInUnits < ActiveRecord::Migration[7.1]
  def change
    change_column_default :units, :corequisite, from: nil, to: "Nil"
    change_column_default :units, :prerequisite, from: nil, to: "Nil"
  end
end
