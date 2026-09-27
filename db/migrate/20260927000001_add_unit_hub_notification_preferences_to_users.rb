# frozen_string_literal: true

# Unit Hub updates get a category of their own, stored as user columns like the
# task, feedback and portfolio categories. Unlike those, email and push are
# separate opt-ins here because an announcement can go to a whole cohort, so
# only the in-app bell is on by default. Session reminders are a fourth opt-in.
class AddUnitHubNotificationPreferencesToUsers < ActiveRecord::Migration[8.0]
  def change
    change_table :users, bulk: true do |t|
      t.boolean :receive_unit_hub_notifications, default: true, null: false
      t.boolean :receive_unit_hub_email_notifications, default: false, null: false
      t.boolean :receive_unit_hub_push_notifications, default: false, null: false
      t.boolean :receive_unit_hub_session_reminders, default: false, null: false
    end
  end
end
