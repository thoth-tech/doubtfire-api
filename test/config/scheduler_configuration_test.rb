require "test_helper"

class SchedulerConfigurationTest < ActiveSupport::TestCase
  test "dead whenever schedule is removed" do
    dead_schedule = Rails.root.join("config/schedule.rb")

    refute dead_schedule.exist?,
           "config/schedule.rb should be removed because whenever is not installed"
  end

  test "schedule owners are documented" do
    schedule = Rails.root.join("config/schedule.yml").read

    assert_includes schedule.lines.first, "Sidekiq-cron"
    assert_includes schedule.lines.first, ".ci-setup/crontab"
  end
end
