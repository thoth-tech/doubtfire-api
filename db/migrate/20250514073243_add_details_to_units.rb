class AddDetailsToUnits < ActiveRecord::Migration[7.1]
  def change
    add_column :units, :credit_points, :integer
  end
end
