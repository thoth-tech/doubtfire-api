# frozen_string_literal: true

# Send the student digest for one cadence.
#
# Nothing scheduled this before. The only recurring summary was one line in
# .ci-setup/crontab, `0 7 * * 1 send_weekly_emails.sh`, which ran the per-unit
# mail and knew nothing about daily or monthly. That line is gone and these
# three cadences replace it, registered in config/schedule.yml.
#
# Sidekiq rather than cron for two reasons. The crontab is only installed by
# lib/shell/pdfgen_entry_point.sh, which runs in the pdfgen container, so a
# deployment without LaTeX has never sent a summary at all and the demo stack
# never will. And CheckUnitSimilarityJob already left that crontab for exactly
# this reason, so following it means one scheduler to keep alive instead of two.
#
# This sends NotificationsMailer#student_digest, one mail per student across all
# their units. The older per-unit NotificationsMailer#weekly_student_summary is
# untouched and still works, but nothing schedules it any more: it is now only
# reachable through `rake mailer:send_status_emails`, run by hand. Both on one
# schedule would mean a student gets the digest and a mail per unit in the same
# morning, which is worse than either on its own.
class SendDigestEmailsJob
  include Sidekiq::Job

  # 'off' is a digest_frequency but it is not a cadence. User#wants_digest_on?
  # only compares the two strings, so a run with cadence 'off' would mail
  # exactly the students who asked for no summary at all.
  CADENCES = (User::DIGEST_FREQUENCIES - ['off']).freeze

  BATCH_SIZE = 100

  # Locked per cadence and not across all three. The three runs mail disjoint
  # sets of students, so daily overtaking weekly is fine, but a second daily
  # starting while the first is still sweeping is not.
  sidekiq_options queue: :mailers,
                  lock: :until_executed,
                  lock_args_method: ->(args) { ["send-digest-emails-#{args.first}"] },
                  on_conflict: :reject,
                  retry: 1

  def perform(cadence = 'weekly')
    cadence = cadence.to_s
    raise ArgumentError, "cadence must be one of #{CADENCES.join(', ')}" unless CADENCES.include?(cadence)

    # The digest mailer is on ui/email-styling and the digest_frequency column
    # is on api/notification-links. Until both are merged a checkout can have
    # this schedule without the mailer it calls. Failing here is deliberate: the
    # run shows up red in Sidekiq rather than quietly mailing nobody, which is
    # how the submission queue managed to sit unread for weeks.
    unless NotificationsMailer.respond_to?(:student_digest)
      raise 'NotificationsMailer#student_digest is missing. The digest mailer is on ui/email-styling and has not merged into this checkout.'
    end

    period = DigestDeliveryGuard.period_for(cadence)

    recipients(cadence).find_each(batch_size: BATCH_SIZE) do |user|
      deliver(user, cadence, period)
    end
  end

  private

  # Who this run mails.
  #
  # digest_frequency picks the cadence, which is User#wants_digest_on? written
  # as a query, and receive_feedback_notifications is still the master switch.
  # Both, because the new column defaults to weekly for everyone, so checking
  # only the cadence would start mailing students who turned summaries off
  # before the preference existed.
  #
  # Joined to projects so a run renders nothing for staff, for graduates and for
  # anyone between trimesters. The mailer returns nil for them, but only after
  # building a summary for every unit first.
  def recipients(cadence)
    User.where(digest_frequency: cadence, receive_feedback_notifications: true)
        .where(id: Project.where(enrolled: true).joins(:unit).where(units: { active: true }).select(:user_id))
  end

  # One student. Claimed before the send and handed back if the send raises, so
  # a delivery that failed is still retryable and one that worked is not
  # repeatable.
  def deliver(user, cadence, period)
    return unless DigestDeliveryGuard.claim(user, period)

    NotificationsMailer.student_digest(user, cadence).deliver_now
  rescue StandardError => e
    DigestDeliveryGuard.release(user, period)

    # Logged and swallowed per student, the same as the per-unit send does. One
    # student with unrenderable data must not stop the rest of the cohort, and
    # a raise here would have Sidekiq retry the whole sweep.
    Rails.logger.error "Failed #{cadence} digest for user #{user.id}: #{e.class} - #{e.message}"
  end
end
