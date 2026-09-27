# frozen_string_literal: true

# RAILS_ENV=test COHORT_SIZE=100 bundle exec rails runner script/benchmark_notifications.rb
# Synthetic transport benchmark. Requires a dedicated populated test DB and an
# empty, dedicated Redis DB; never points at SMTP or a browser push provider.
abort 'Run only in test with an isolated database' unless Rails.env.test?
require 'sidekiq/api'
require 'factory_bot_rails'
require 'faker'
FactoryBot.find_definitions unless FactoryBot.factories.registered?(:user)

size = Integer(ENV.fetch('COHORT_SIZE'), 10)
abort 'COHORT_SIZE must be between 1 and 20000' unless size.between?(1, 20_000)
opt_out_percent = Integer(ENV.fetch('OPT_OUT_PERCENT', '20'), 10)
abort 'OPT_OUT_PERCENT must be between 0 and 100' unless opt_out_percent.between?(0, 100)
queues = %w[mailers notifications].map { |name| Sidekiq::Queue.new(name) }
abort 'Use an empty dedicated Redis DB; delivery queues are not empty' unless queues.all? { |queue| queue.size.zero? } # rubocop:disable Style/ZeroLengthPredicate
redis_database = URI.parse(ENV.fetch('DF_REDIS_SIDEKIQ_URL', '')).path.delete_prefix('/')
abort 'Use Redis DB 1 or higher for this isolated benchmark' unless redis_database.match?(/\A\d+\z/) && redis_database.to_i.positive?

ActionMailer::Base.delivery_method = :test
ActionMailer::Base.perform_deliveries = true
push_deliveries = 0
WebPush.singleton_class.define_method(:payload_send) do |**_args|
  push_deliveries += 1
  true
end
key = WebPush.generate_key
ENV['DOUBTFIRE_VAPID_PUBLIC_KEY'] = key.public_key
ENV['DOUBTFIRE_VAPID_PRIVATE_KEY'] = key.private_key
ENV['DOUBTFIRE_NOTIFICATION_RECIPIENT_LIMIT'] = '100'
clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
rss = lambda do
  File.read('/proc/self/status')[/^VmRSS:\s+(\d+)/, 1].to_i
rescue Errno::ENOENT
  nil
end
users = []
results = []
nonce = SecureRandom.hex(8)

begin
  size.times do |index|
    user = FactoryBot.create(:user, email: "notification-benchmark-#{nonce}-#{index}@example.invalid",
                                    receive_feedback_notifications: index * 100 / size >= opt_out_percent)
    users << user
    PushSubscription.create!(user: user, endpoint: "https://fcm.googleapis.com/fcm/send/#{nonce}-#{index}",
                             p256dh: key.public_key, auth: Base64.urlsafe_encode64(SecureRandom.random_bytes(16), padding: false))
  end
  user_ids = users.map(&:id)
  eligible_recipients = users.count(&:receive_feedback_notifications)
  peaks = {}
  peak_lock = Mutex.new
  observe = lambda do
    peak_lock.synchronize do
      peaks[:queue_depth] = [peaks[:queue_depth], queues.sum(&:size)].max
      current_rss = rss.call
      peaks[:rss_kib] = [peaks[:rss_kib].to_i, current_rss.to_i].max
    end
  end

  drain = lambda do
    queues.each do |queue|
      queue.each do |job|
        klass = { 'NotificationEmailJob' => NotificationEmailJob,
                  'PushNotificationDeliveryJob' => PushNotificationDeliveryJob }.fetch(job.klass)
        klass.new.perform(*job.args)
        job.delete
        observe.call
      end
    end
  end

  [[:inline_baseline, 1], [:queued, 1], [:concurrent_queued, 2]].each do |mode, events|
    ActionMailer::Base.deliveries.clear
    push_deliveries = 0
    peaks = { queue_depth: 0, rss_kib: rss.call }
    event_prefix = "benchmark_#{nonce}_#{mode}"
    started = clock.call
    emit = lambda do |event_number|
      users.each do |user|
        user = User.find(user.id) if events > 1
        NotificationService.notify(user: user, type: 'feedback', event: "#{event_prefix}_#{event_number}",
                                   message: 'Synthetic notification benchmark', link: '/notifications')
        observe.call
        drain.call if mode == :inline_baseline
      end
    end
    if events > 1
      events.times.map do |event_number|
        Thread.new { ActiveRecord::Base.connection_pool.with_connection { emit.call(event_number) } }
      end.each(&:value)
    else
      emit.call(0)
    end
    enqueue_seconds = clock.call - started
    drain_started = clock.call
    drain.call
    finished = clock.call
    expected_deliveries = eligible_recipients * events
    notifications = Notification.where(user_id: user_ids, event: events.times.map { |index| "#{event_prefix}_#{index}" })
    observed = { notifications: notifications.count,
                 email_states: notifications.group(:email_delivery_state).count,
                 email_attempts: notifications.sum(:email_delivery_attempts),
                 synthetic_emails: ActionMailer::Base.deliveries.length,
                 synthetic_pushes: push_deliveries,
                 remaining_queue_depth: queues.sum(&:size) }
    expected_states = expected_deliveries.zero? ? {} : { 'delivered' => expected_deliveries }
    unless observed == { notifications: expected_deliveries, email_states: expected_states,
                         email_attempts: expected_deliveries, synthetic_emails: expected_deliveries,
                         synthetic_pushes: expected_deliveries, remaining_queue_depth: 0 }
      abort "Delivery count verification failed for #{mode}: #{observed.to_json}"
    end
    results << { mode: mode, cohort_size: size, simultaneous_events: events,
                 opt_out_percent: opt_out_percent, eligible_recipients: eligible_recipients,
                 suppressed_recipients: size - eligible_recipients, trigger_seconds: enqueue_seconds.round(4),
                 drain_seconds: (finished - drain_started).round(4), total_seconds: (finished - started).round(4),
                 peak_observed_queue_depth: peaks[:queue_depth], peak_observed_rss_kib: peaks[:rss_kib],
                 verified_delivery_counts: observed }
  end
  report = { transport: 'synthetic mail and push; no external delivery',
             source_revision: ENV.fetch('BENCHMARK_SOURCE_REVISION', nil),
             ruby_version: RUBY_VERSION, rails_version: Rails.version,
             database_version: ActiveRecord::Base.connection.database_version.to_s,
             recipient_limit_for_benchmark: 100,
             configured_fanout_limit: NotificationDeliveryPolicy.positive_integer('DOUBTFIRE_NOTIFICATION_FANOUT_LIMIT', 500),
             actual_largest_enrolment: ENV.fetch('LARGEST_UNIT_ENROLMENT', nil),
             note: 'Direct service timing, including sampling; bypasses cohort admission. One drain worker; sampled peaks; fixed mode order without warm-up.',
             results: results }
ensure
  Notification.where(user_id: users.map(&:id)).delete_all
  PushSubscription.where(user_id: users.map(&:id)).delete_all
  users.each(&:destroy!)
end
report[:cleanup_verified] = User.where(id: user_ids).none? && Notification.where(user_id: user_ids).none? &&
                            PushSubscription.where(user_id: user_ids).none? && queues.sum(&:size).zero?
abort 'Synthetic fixture cleanup failed' unless report[:cleanup_verified]

json = JSON.pretty_generate(report)
File.write(ENV.fetch('BENCHMARK_RESULT_PATH'), "#{json}\n") if ENV['BENCHMARK_RESULT_PATH'].present?
puts json
