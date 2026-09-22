class ChangeNotificationMessageToText < ActiveRecord::Migration[8.0]
  # The model allows a 500 character message, but the column was created as a
  # string, which MariaDB stores as VARCHAR(255). Anything over 255 characters
  # passed validation and then failed at the database. TEXT holds the full
  # validated length.
  def up
    change_column :notifications, :message, :text, null: false
  end

  # Lossy. Narrowing back to VARCHAR(255) will reject (strict mode) or silently
  # truncate (permissive mode) any message over 255 characters saved while the
  # column was text. Only roll this back on a database you are willing to lose
  # long messages from.
  def down
    change_column :notifications, :message, :string, null: false
  end
end
