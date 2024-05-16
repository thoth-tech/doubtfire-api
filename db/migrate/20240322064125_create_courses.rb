class CreateCourses < ActiveRecord::Migration[7.0]
  def change
    create_table :courses do |t|
      t.string :name
      t.string :code
      t.integer :year
      t.string :version
      t.string :url

      t.timestamps
    end
  end
end
