namespace :mailer do
  # The student digest, one mail per student across every unit they are in.
  #
  # The scheduled runs are in config/schedule.yml and go through
  # SendDigestEmailsJob. This is the same sweep, run now and in this process,
  # for an operator who wants one cadence sent by hand. Running it does not
  # double up on a scheduled run, because the job claims each student for the
  # period before mailing them.
  #
  # CADENCE picks which students are in scope: it must match their chosen
  # digest_frequency. 'off' is rejected, because a run with that cadence would
  # mail the students who asked for nothing.
  #
  # This is not mailer:send_status_emails. That one is the older per-unit mail
  # and it still sends what it always sent.
  task send_digests: :environment do
    SendDigestEmailsJob.new.perform(ENV.fetch('CADENCE', 'weekly'))
  end
end
