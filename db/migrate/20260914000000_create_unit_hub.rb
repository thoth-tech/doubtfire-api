# frozen_string_literal: true

class CreateUnitHub < ActiveRecord::Migration[8.0]
  def change
    create_table :unit_announcements, charset: 'utf8mb4', collation: 'utf8mb4_general_ci' do |t|
      t.references :unit, null: false, foreign_key: true
      t.references :author, null: true, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :title, null: false, limit: 200
      t.text :body, null: false
      t.string :source_url, limit: 2048
      t.boolean :pinned, null: false, default: false
      t.datetime :published_at
      t.datetime :expires_at
      t.timestamps
      t.index [:unit_id, :published_at]
    end

    create_table :unit_learning_sessions, charset: 'utf8mb4', collation: 'utf8mb4_general_ci' do |t|
      t.references :unit, null: false, foreign_key: true
      t.references :author, null: true, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :title, null: false, limit: 200
      t.text :description
      t.string :kind, null: false, default: 'helphub'
      t.datetime :start_at, null: false
      t.datetime :end_at, null: false
      t.string :timezone, null: false, default: 'Australia/Melbourne'
      t.string :location, limit: 300
      t.string :join_url, limit: 2048
      t.string :source_url, limit: 2048
      t.boolean :published, null: false, default: false
      t.boolean :cancelled, null: false, default: false
      t.string :recurrence, null: false, default: 'none'
      t.date :recurrence_until
      t.timestamps
      t.index [:unit_id, :published, :start_at], name: 'index_unit_sessions_for_feed'
    end

    add_column :webcals, :include_learning_sessions, :boolean, null: false, default: false
  end
end
