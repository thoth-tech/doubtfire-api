class CreateNotifications < ActiveRecord::Migration[8.0]
  def change
    create_table :notifications do |t|
      t.references :user, foreign_key: true, null: false
      t.string :notification_type, null: false
      t.string :message, null: false
      t.string :link
      t.datetime :read_at

      t.timestamps
    end

    add_index :notifications, [:user_id, :read_at]
  end
end
