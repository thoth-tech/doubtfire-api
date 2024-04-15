class CreateCoursemaps < ActiveRecord::Migration[7.0]
  def change
    create_table :coursemaps do |t|
      t.integer :userId
      t.integer :courseId

      t.timestamps
    end
  end
end
