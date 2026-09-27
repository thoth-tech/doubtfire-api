# frozen_string_literal: true

# Stops a student getting two copies of the same summary email.
#
# The digest had no guard of any kind. Project#send_weekly_status_email calls
# the mailer with deliver_now and records nothing afterwards, so every extra run
# of a cadence was another copy in every inbox: a schedule that fires twice, an
# operator running the rake task to see what it does, or a worker that died
# halfway through a sweep and had Sidekiq retry the whole thing. One line in a
# crontab hid that, because one line cannot fire twice.
#
# A claim is one Redis key per student per run period, held a little longer than
# the period so a late repeat still finds it. Redis rather than a table because
# the claim is worthless once its period is over and Sidekiq already needs Redis
# for the job to exist at all. The production redis-sidekiq runs with appendonly
# on, so claims survive a restart of that container.
#
# Claimed immediately before the send and released if the send raises, so a
# delivery that failed is still retryable and one that worked is not repeatable.
class DigestDeliveryGuard
  # How long a claim outlives its own period. Long enough for a run that is late
  # or repeated, short enough that nothing accumulates.
  TTL = {
    'daily' => 2.days,
    'weekly' => 2.weeks,
    'monthly' => 70.days
  }.freeze

  DEFAULT_TTL = 2.weeks

  # Name the period a run belongs to.
  #
  # Local time and not Time.zone, deliberately. The app leaves config.time_zone
  # at UTC, but sidekiq-cron reads config/schedule.yml in the process zone, so
  # "7am" is 7am in TZ. Naming the period the same way is what keeps a second
  # run on the same local day inside the same period. On UTC dates the 7am
  # Melbourne run lands at 21:00 the evening before, and a re-run a few hours
  # later would fall on the next UTC date and mail everybody again.
  # getlocal rather than a bare Time.now only because Rails/TimeZone wants the
  # zone said out loud. It is the process zone either way, which is the point.
  def self.period_for(cadence, now = Time.now.getlocal)
    case cadence.to_s
    when 'daily' then "daily:#{now.strftime('%Y-%m-%d')}"
    when 'weekly' then "weekly:#{now.strftime('%G-W%V')}"
    when 'monthly' then "monthly:#{now.strftime('%Y-%m')}"
    end
  end

  # True when this run is the one that gets to mail this user.
  def self.claim(user, period)
    return true if period.blank?

    ttl = TTL.fetch(period.split(':').first, DEFAULT_TTL).to_i

    Sidekiq.redis { |redis| redis.call('SET', key(user, period), '1', 'NX', 'EX', ttl) } == 'OK'
  rescue StandardError => e
    # A guard that cannot answer says no. If Redis is unreachable then so is the
    # only record of who has already been mailed, and a second copy of a summary
    # is worse than a summary that is one period late.
    Rails.logger.error "Digest guard unavailable for user #{user.id}: #{e.class} - #{e.message}"
    false
  end

  # Hand the period back after a send that raised.
  def self.release(user, period)
    return if period.blank?

    Sidekiq.redis { |redis| redis.call('DEL', key(user, period)) }
  rescue StandardError => e
    Rails.logger.error "Digest guard could not release user #{user.id}: #{e.class} - #{e.message}"
  end

  def self.key(user, period)
    "doubtfire:digest:#{period}:#{user.id}"
  end
  private_class_method :key
end
