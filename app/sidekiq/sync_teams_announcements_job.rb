# frozen_string_literal: true

class SyncTeamsAnnouncementsJob
  include Sidekiq::Job
  sidekiq_options queue: :default, retry: false, lock: :until_executed, lock_ttl: 300

  def perform
    UnitHub::Teams::AnnouncementSync.new.call
  rescue UnitHub::Teams::Configuration::Error
    Rails.logger.warn('Teams announcement sync configuration is invalid; no messages imported.')
  end
end
