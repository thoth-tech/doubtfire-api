# frozen_string_literal: true

require Rails.root.join('lib/demo_data/all_features_scenario')

namespace :db do
  desc 'Recreate the guarded, local all-features demo dataset'
  task all_features_demo: :environment do
    Rails.logger.level = Logger::INFO
    result = DemoData::AllFeaturesScenario.run!

    puts "All-features demo data is ready: #{result.inspect}"
  end

  desc 'Verify the guarded all-features demo dataset without changing it'
  task all_features_demo_verify: :environment do
    result = DemoData::AllFeaturesScenario.verify!

    puts "All-features demo data passed verification: #{result.inspect}"
  end

  desc 'Remove only the guarded all-features demo dataset'
  task all_features_demo_cleanup: :environment do
    Rails.logger.level = Logger::INFO
    DemoData::AllFeaturesScenario.cleanup!

    puts 'All-features demo data has been removed.'
  end
end
