namespace :mailer do
  # The older per-unit summary, one mail per student per unit.
  #
  # Nothing schedules this any more. It ran from .ci-setup/crontab every Monday
  # at 7am and that line is gone: config/schedule.yml now runs the student
  # digest instead, which is one mail covering all of a student's units. Both on
  # a schedule would mean a student gets the digest and a mail per unit in the
  # same morning. Whether the digest supersedes this outright is a call for the
  # team, so this is left working and reachable by hand rather than deleted.
  #
  # CADENCE picks which students are in scope: it must match their chosen
  # digest_frequency. 'off' is rejected, because User#wants_digest_on? only
  # compares the two strings, so that run would mail exactly the students who
  # asked for no summary at all.
  #
  # There is no guard on this one. It sends with deliver_now and records
  # nothing, so running it twice sends two copies. The digest has a guard;
  # see DigestDeliveryGuard.
  task send_status_emails: :environment do
    summary_stats = {}

    cadence = ENV.fetch('CADENCE', 'weekly')
    raise ArgumentError, "CADENCE must be one of #{SendDigestEmailsJob::CADENCES.join(', ')}" unless SendDigestEmailsJob::CADENCES.include?(cadence)

    summary_stats[:cadence] = cadence

    summary_stats[:week_end] = Time.zone.now
    summary_stats[:week_start] = summary_stats[:week_end] - { 'daily' => 1.day, 'weekly' => 7.days, 'monthly' => 1.month }.fetch(cadence, 7.days)
    summary_stats[:weeks_comments] = TaskComment.where("created_at >= :start AND created_at < :end", start: summary_stats[:week_start], end: summary_stats[:week_end]).count
    summary_stats[:weeks_engagements] = TaskEngagement.where("engagement_time >= :start AND engagement_time < :end", start: summary_stats[:week_start], end: summary_stats[:week_end]).count

    Unit.where(active: true).find_each do |unit|
      next unless summary_stats[:week_end] > unit.start_date && summary_stats[:week_start] < unit.end_date

      unit.send_weekly_status_emails(summary_stats)
    end
  end
end
