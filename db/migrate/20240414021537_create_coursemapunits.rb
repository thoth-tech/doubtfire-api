class CreateCoursemapunits < ActiveRecord::Migration[7.0]
  def change
    create_table :coursemapunits do |t|
      t.integer :courseMapId
      t.integer :unitId
      t.integer :yearSlot
      t.integer :teachingPeriodSlot
      t.integer :unitSlot

      t.timestamps
    end
  end
end
