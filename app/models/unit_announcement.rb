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

  private

  def expiry_follows_publication
    return unless published_at && expires_at && expires_at <= published_at

    errors.add(:expires_at, 'must be after publication')
  end
end
