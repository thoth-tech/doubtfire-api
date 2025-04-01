class AddTotalTutorTimeToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :total_tutor_time, :decimal, precision: 10, scale: 2, null: false, default: 0.0
  end
end
