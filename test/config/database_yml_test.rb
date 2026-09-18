require 'test_helper'

class DatabaseYmlTest < ActiveSupport::TestCase
  # Load config/database.yml the same way Rails does, through ERB, and assert
  # every deployed environment pins the same utf8mb4 client charset. Without it
  # production and staging inherit whatever the server image defaults to, so a
  # comment containing an emoji or a CJK character saves in test and raises
  # Mysql2::Error: Incorrect string value in production.
  def database_config
    raw = File.read(Rails.root.join('config', 'database.yml'))
    YAML.safe_load(ERB.new(raw).result, aliases: true)
  end

  def test_every_environment_sets_utf8mb4_encoding_and_collation
    config = database_config

    %w[development test staging production].each do |env|
      assert_equal 'utf8mb4', config[env]['encoding'],
                   "#{env} must pin the utf8mb4 client encoding"
      assert_equal 'utf8mb4_general_ci', config[env]['collation'],
                   "#{env} must pin the utf8mb4_general_ci collation"
    end
  end
end
