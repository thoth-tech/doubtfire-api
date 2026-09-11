# frozen_string_literal: true

class AddDetailedPeerProgress < ActiveRecord::Migration[8.0]
  def change
    # Internal aggregate counts only. Exact upload counts are required so the
    # student API can subtract the authenticated viewer before quantisation;
    # reconstructing a count from the legacy rounded percentage is unsafe.
    add_column :peer_progress_snapshots, :submitted_count, :integer
    add_column :peer_progress_snapshots, :status_counts, :json

    # Existing and future users start opted in, while the profile endpoint can
    # persist an explicit false value.
    add_column :users,
               :display_peer_progress,
               :boolean,
               default: true,
               null: false
  end
end
