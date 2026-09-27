# frozen_string_literal: true

class TeamsAnnouncementSyncState < ApplicationRecord
  belongs_to :unit
  validates :mapping_key, presence: true
  validates :status, inclusion: { in: %w[pending synced failed throttled] }
end
