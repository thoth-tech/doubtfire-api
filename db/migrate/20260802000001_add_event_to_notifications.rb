class AddEventToNotifications < ActiveRecord::Migration[8.0]
  # `notification_type` is the broad category the user's preferences switch on
  # (task, feedback, portfolio, extension, general). `event` records which
  # specific thing happened, so a notification can be traced back to the code
  # that raised it and so we can later suppress or batch a single event without
  # turning off the whole category.
  def up
    # Added with a placeholder default first, so the ALTER succeeds on a
    # database that already has notification rows, then the default is dropped
    # so new records must supply a real event.
    add_column :notifications, :event, :string, null: false, default: 'legacy'
    change_column_default :notifications, :event, nil

    add_index :notifications, [:user_id, :event]
  end

  def down
    remove_index :notifications, column: [:user_id, :event]
    remove_column :notifications, :event
  end
end
