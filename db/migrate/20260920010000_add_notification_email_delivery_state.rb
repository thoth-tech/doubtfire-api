# frozen_string_literal: true

class AddNotificationEmailDeliveryState < ActiveRecord::Migration[8.0]
  def change
    # Historical rows have no reliable delivery evidence. Do not call them sent
    # or queue them again when the migration runs.
    add_column :notifications, :email_delivery_state, :string, default: 'untracked', null: false
    add_column :notifications, :email_delivery_attempts, :integer, default: 0, null: false
    add_column :notifications, :email_delivered_at, :datetime
    add_column :notifications, :email_delivery_error_class, :string
    add_index :notifications, :email_delivery_state
    add_index :notifications, [:user_id, :created_at], name: 'index_notifications_on_recipient_rate_window'
  end
end
