# frozen_string_literal: true

require 'test_helper'
require 'sidekiq_unique_jobs/testing'

class TiiCheckProgressJobTest < ActiveSupport::TestCase
  def test_jobs_are_scheduled
    # Clear fake jobs and any unique-job locks left by an earlier test run.
    Sidekiq::Job.clear_all
    Sidekiq::Cron::Job.destroy_all!
    Sidekiq::Cron::Job.load_from_hash!(
      YAML.load_file(Rails.root.join('config/schedule.yml'))
    )

    jobs = Sidekiq::Cron::Job.all
    peer_progress_job =
      jobs.find { |job| job.name == 'aggregate_peer_progress' }

    assert_equal 9, jobs.count, jobs.map(&:name)
    assert_not_nil peer_progress_job
    assert_equal 'AggregatePeerProgressJob', peer_progress_job.klass

    # Sidekiq::Cron::Job.all returns an Array, not an ActiveRecord relation.
    jobs.each(&:enqueue!)

    assert_equal 1, TiiRegisterWebHookJob.jobs.count
    assert_equal 1, TiiCheckProgressJob.jobs.count
    assert_equal 1, ClearAccessTokensJob.jobs.count
    assert_equal 1, RefreshModerationFeedbackTimestampsJob.jobs.count
    assert_equal 1, AggregatePeerProgressJob.jobs.count
    assert_equal 1, AggregateTaskCompletionStatsJob.jobs.count
    assert_equal 1, PollCommunicationSetSchedulesJob.jobs.count
    assert_equal 1, SendNewTaskAvailableNotificationsJob.jobs.count
    assert_equal 1, SendDueSoonRemindersJob.jobs.count
    # assert_equal 1, ArchiveOldUnitsJob.jobs.count
  end
end
