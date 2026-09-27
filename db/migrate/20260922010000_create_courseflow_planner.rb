class CreateCourseflowPlanner < ActiveRecord::Migration[8.0]
  def change
    create_table :courseflow_courses do |t|
      t.string :code, limit: 40, null: false
      t.string :name, limit: 200, null: false
      t.string :version, limit: 40, null: false
      t.integer :elective_count, null: false
      t.json :units, null: false
      t.timestamps
      t.index [:code, :version], unique: true
    end

    create_table :courseflow_maps do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :course, null: false, foreign_key: { to_table: :courseflow_courses }
      t.string :name, limit: 200, null: false
      t.json :periods, null: false
      t.json :slots, null: false
      t.integer :lock_version, default: 0, null: false
      t.timestamps
    end
  end
end
