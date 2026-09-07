# frozen_string_literal: true

class AddPeerProgressEnabledToUnits < ActiveRecord::Migration[8.0]
  def change
    add_column :units,
               :peer_progress_enabled,
               :boolean,
               default: false,
               null: false
  end
end
