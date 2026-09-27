# frozen_string_literal: true

class AddTeamsAnnouncementSources < ActiveRecord::Migration[8.0]
  def change
    add_column :unit_announcements, :source_provider, :string, null: false, default: 'manual'
    add_column :unit_announcements, :external_source_key, :string, limit: 64
    add_column :unit_announcements, :source_mapping_key, :string, limit: 64
    add_column :unit_announcements, :source_channel_key, :string, limit: 64
    add_column :unit_announcements, :external_message_id, :string, limit: 128
    add_column :unit_announcements, :source_updated_at, :datetime
    add_column :unit_announcements, :source_imported_at, :datetime
    add_column :unit_announcements, :source_checked_at, :datetime
    add_index :unit_announcements, [:unit_id, :external_source_key], unique: true, name: 'index_announcements_external_source'
    add_index :unit_announcements, [:source_mapping_key, :source_checked_at], name: 'index_announcements_source_scan'
    create_table :teams_announcement_sync_states, charset: 'utf8mb4', collation: 'utf8mb4_general_ci' do |t|
      t.references :unit, null: false, foreign_key: true
      t.string :mapping_key, null: false, limit: 64
      t.string :status, null: false, default: 'pending'
      t.datetime :last_attempt_at
      t.datetime :last_succeeded_at
      t.datetime :next_attempt_at
      t.timestamps
      t.index :mapping_key, unique: true
    end
  end
end
