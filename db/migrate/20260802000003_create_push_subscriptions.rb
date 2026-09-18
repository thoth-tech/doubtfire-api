class CreatePushSubscriptions < ActiveRecord::Migration[8.0]
  def change
    create_table :push_subscriptions do |t|
      t.references :user, foreign_key: true, null: false

      # The push service URL the browser hands us. We send to it, and it
      # identifies the browser rather than the person, so it is unique across
      # the whole table and not just per user.
      #
      # 500 rather than the default 255 because Firefox and Safari endpoints
      # run close to 260 characters. A varchar(255) would reject them under
      # strict mode and silently truncate them otherwise, and a truncated
      # endpoint is a push that quietly goes nowhere. utf8mb4 makes this a
      # 2000 byte index key, inside InnoDB's 3072 byte limit.
      t.string :endpoint, null: false, limit: 500

      # The browser's public key and auth secret. The payload is encrypted to
      # these, so without them a push cannot be read by the browser that asked
      # for it.
      t.string :p256dh, null: false
      t.string :auth, null: false

      t.timestamps
    end

    add_index :push_subscriptions, :endpoint, unique: true
  end
end
