Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch('DF_REDIS_SIDEKIQ_URL', 'redis://localhost:6379/1') }
  config.logger = Rails.logger

  config.client_middleware do |chain|
    chain.add SidekiqUniqueJobs::Middleware::Client
  end

  config.server_middleware do |chain|
    chain.add SidekiqUniqueJobs::Middleware::Server
  end

  SidekiqUniqueJobs::Server.configure(config)

  Sidekiq::Status.configure_server_middleware(config, expiration: 30.minutes.to_i)
  Sidekiq::Status.configure_client_middleware(config, expiration: 30.minutes.to_i)

  config.on(:startup) do
    schedule_file = Rails.root.join('config/schedule.yml')

    # 'source' => 'schedule' is what makes the bang in load_from_hash! do
    # anything. It calls destroy_removed_jobs, which only ever considers jobs
    # whose source is "schedule", and Sidekiq::Cron::Job defaults every other
    # job to "dynamic". Loading without it registered all of these as dynamic,
    # so a job deleted or renamed in this file was never removed from Redis: it
    # kept its schedule and kept firing, and after a rename both the old name
    # and the new one ran. The key has to be a string, because the job reads
    # args["source"] out of a hash that YAML filled with string keys.
    #
    # Jobs added by hand in the Sidekiq web UI stay dynamic and are still left
    # alone, which is the point of the distinction. Entries already in Redis
    # from before this change are also still dynamic, so each one has to be
    # destroyed once by hand or it will outlive its line in this file.
    if File.exist?(schedule_file)
      Sidekiq::Cron::Job.load_from_hash!(YAML.load_file(schedule_file), 'source' => 'schedule')
    end
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch('DF_REDIS_SIDEKIQ_URL', 'redis://localhost:6379/1') }
  config.logger = Rails.logger

  config.client_middleware do |chain|
    chain.add SidekiqUniqueJobs::Middleware::Client
  end

  Sidekiq::Status.configure_client_middleware(config, expiration: 30.minutes.to_i)
end
