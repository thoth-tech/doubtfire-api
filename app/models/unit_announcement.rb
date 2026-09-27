# frozen_string_literal: true

class UnitAnnouncement < ApplicationRecord
  include UnitHubLinks

  belongs_to :unit
  belongs_to :author, class_name: 'User', optional: true

  validates :title, presence: true, length: { maximum: 200 }
  validates :body, presence: true, length: { maximum: 20_000 }
  validates :pinned, inclusion: { in: [true, false] }
  validates :source_provider, inclusion: { in: %w[manual microsoft_teams] }
  validate :expiry_follows_publication

  scope :allowed_sources, lambda {
    where(source_provider: 'manual').or(where(source_provider: 'microsoft_teams', source_mapping_key: UnitHub::Teams::Configuration.new.visible_mapping_keys))
  }
  scope :visible_at, lambda { |at|
    allowed_sources.where('published_at <= ?', at).where('expires_at IS NULL OR expires_at > ?', at)
  }
  scope :recent_first, -> { order(pinned: :desc, published_at: :desc, id: :desc) }

  # After commit, so the job that fans out never runs before the row it reads
  # is visible, and a rolled back save tells nobody anything.
  after_commit(on: :create) { queue_hub_notifications(created: true) }
  after_commit(on: :update) { queue_hub_notifications(created: false) }

  private

  # A notification must never stop an announcement being saved.
  def queue_hub_notifications(created:)
    UnitHub::Notifications.announcement_committed(self, created: created)
  rescue StandardError => e
    Rails.logger.error("Failed to queue Unit Hub notifications for UnitAnnouncement #{id}: #{e.class}")
  end

  def expiry_follows_publication
    return unless published_at && expires_at && expires_at <= published_at

    errors.add(:expires_at, 'must be after publication')
  end
end
