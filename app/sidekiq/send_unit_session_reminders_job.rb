# frozen_string_literal: true

# Remind people who opted in that a Unit Hub session starts soon.
#
# Nobody saves anything when a session approaches, so this is swept for on a
# schedule like SendDueSoonRemindersJob. config/schedule.yml runs it every five
# minutes. Each run looks for occurrences starting within REMINDER_LEAD, so one
# occurrence is seen by several runs. The dedupe key names the occurrence by
# its start time, which makes every run after the first find the row already
# there, and a run that is late still reminds anyone before the start.
class SendUnitSessionRemindersJob
  include Sidekiq::Job

  sidekiq_options queue: :notifications,
                  lock: :until_executed,
                  lock_args_method: ->(_args) { ['send-unit-session-reminders'] },
                  on_conflict: :reject,
                  retry: 1

  def perform
    now = Time.current
    horizon = now + UnitHub::Notifications::REMINDER_LEAD
    failures = []

    candidates(now, horizon).find_each do |session|
      session.occurrences(from: now, to: horizon).each do |occurrence|
        next unless occurrence[:start_at] > now && occurrence[:start_at] <= horizon

        remind(session, occurrence[:start_at])
      end
    rescue StandardError => e
      failures << session.id
      Rails.logger.error("Failed session reminders for UnitLearningSession #{session.id}: #{e.class}")
    end

    raise "Session reminders failed for sessions: #{failures.join(', ')}" if failures.any?
  end

  private

  def candidates(now, horizon)
    UnitLearningSession.joins(:unit)
                       .where(units: { active: true }, published: true, cancelled: false)
                       .where(start_at: ..horizon)
                       .where('unit_learning_sessions.end_at >= ? OR unit_learning_sessions.recurrence_until >= ?', now, now.to_date - 1)
                       .includes(:unit)
  end

  def remind(session, start_at)
    event = UnitHub::Notifications::SESSION_STARTING_SOON
    UnitHub::Notifications.fan_out(
      scope: UnitHub::Notifications.recipients(session.unit, author_id: session.author_id)
                                   .where(receive_unit_hub_session_reminders: true),
      event: event,
      dedupe_key: "#{event}:#{session.id}:#{start_at.to_i}",
      notifiable: session,
      message: UnitHub::Notifications.session_starting_soon_message(session, start_at),
      link: UnitHub::Notifications.session_link(session)
    )
  end
end
