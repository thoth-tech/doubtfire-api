class TrackNewTaskNotifications < ActiveRecord::Migration[8.0]
  def up
    # The database default covers definitions written by an older application
    # instance during a rolling deployment. Supported workflows replace it
    # with their actual tracking boundary once configuration is complete.
    unless column_exists?(:task_definitions, :new_task_notifications_from)
      add_column(
        :task_definitions,
        :new_task_notifications_from,
        :datetime,
        default: -> { 'UTC_TIMESTAMP()' }
      )
    end

    unless index_exists?(:task_definitions, :new_task_notifications_from)
      add_index :task_definitions, :new_task_notifications_from
    end

    unless column_exists?(:notifications, :dedupe_key)
      add_column :notifications, :dedupe_key, :string, limit: 191
    end
    unless column_exists?(:notifications, :delivered_at)
      add_column :notifications, :delivered_at, :datetime
    end

    unless index_exists?(:notifications, [:user_id, :dedupe_key], unique: true)
      add_index(
        :notifications,
        [:user_id, :dedupe_key],
        unique: true,
        name: 'index_notifications_on_user_and_dedupe_key'
      )
    end
  end

  def down
    if index_exists?(:notifications, [:user_id, :dedupe_key], name: 'index_notifications_on_user_and_dedupe_key')
      remove_index :notifications, name: 'index_notifications_on_user_and_dedupe_key'
    end
    remove_column :notifications, :delivered_at if column_exists?(:notifications, :delivered_at)
    remove_column :notifications, :dedupe_key if column_exists?(:notifications, :dedupe_key)

    if index_exists?(:task_definitions, :new_task_notifications_from)
      remove_index :task_definitions, :new_task_notifications_from
    end
    if column_exists?(:task_definitions, :new_task_notifications_from)
      remove_column :task_definitions, :new_task_notifications_from
    end
  end
end
