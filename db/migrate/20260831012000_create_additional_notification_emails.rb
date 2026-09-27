class CreateAdditionalNotificationEmails < ActiveRecord::Migration[8.0]
  # Pin the project's standard table options so these tables match every
  # other table even when the database default collation differs. Current
  # MariaDB images, including the 12.3 one CI uses, default utf8mb4 to
  # utf8mb4_uca1400_ai_ci.
  TABLE_OPTIONS = 'ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci'

  def change
    create_table :additional_notification_emails, options: TABLE_OPTIONS do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :email, null: false, limit: 254
      t.integer :verification_version, null: false, default: 0
      t.datetime :verification_sent_at
      t.datetime :verification_expires_at
      t.datetime :verified_at

      t.timestamps
    end

    create_table :additional_notification_email_audits, options: TABLE_OPTIONS do |t|
      t.references :user, null: false, foreign_key: true
      t.string :event, null: false, limit: 64

      t.timestamps
    end

    add_index :additional_notification_email_audits,
              %i[user_id event created_at],
              name: 'idx_additional_email_audits_user_event_time'
  end
end
