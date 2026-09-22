# frozen_string_literal: true

namespace :teams do
  desc 'Sync configured student-visible Teams announcements using application credentials'
  task sync_announcements: :environment do
    result = UnitHub::Teams::AnnouncementSync.new.call
    puts "Teams announcement sync: #{result[:status]}; synced mappings: #{result[:synced]}; failed mappings: #{result[:failed]}."
  rescue UnitHub::Teams::Configuration::Error
    abort 'Teams announcement sync configuration is invalid. Check the operator setup guide.'
  end
end
