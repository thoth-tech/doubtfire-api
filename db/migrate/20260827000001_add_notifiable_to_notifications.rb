class AddNotifiableToNotifications < ActiveRecord::Migration[8.0]
  # A notification records what happened (`event`) but never what it happened
  # to, so the only tie back to the source is the `link` string. Two comments on
  # the same task produce the identical link, so nothing can be joined on it.
  #
  # `notifiable` is polymorphic rather than a `task_id` because the targets
  # already on the board are not all tasks: portfolio submission and extension
  # events point at other records.
  #
  # Nullable, and no backfill. A `general` notification legitimately has no
  # target, and there is no honest way to work out what an existing row referred
  # to. A guess written into the database is worse than a null.
  def up
    # The default single column index on `notifiable_type` is useless here,
    # every lookup carries both halves, so the compound index is added by hand.
    add_reference :notifications, :notifiable, polymorphic: true, null: true, index: false
    add_index :notifications, [:notifiable_type, :notifiable_id]
  end

  def down
    remove_index :notifications, column: [:notifiable_type, :notifiable_id]
    remove_reference :notifications, :notifiable, polymorphic: true
  end
end
