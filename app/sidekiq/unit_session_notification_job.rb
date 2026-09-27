# frozen_string_literal: true

# Tell a unit that a learning session moved, changed where it runs, or was
# cancelled. Queued by UnitHub::Notifications.session_committed after the save
# commits, with the session id, its lock_version and which kind of change.
class UnitSessionNotificationJob
  include Sidekiq::Job

  CHANGES = %w[changed cancelled].freeze

  sidekiq_options queue: :notifications,
                  lock: :until_executed,
                  on_conflict: :reject,
                  retry: 3

  def perform(session_id, version, change)
    return unless CHANGES.include?(change)

    session = UnitLearningSession.find_by(id: session_id)
    return if session.nil? || !session.published

    # A later save may have changed the answer. A session cancelled since a
    # time change hears about the cancellation from its own job, and one put
    # back on since a cancellation hears it is back on.
    return if (change == 'cancelled') != session.cancelled

    event = UnitHub::Notifications::SESSION_CHANGED
    UnitHub::Notifications.fan_out(
      scope: UnitHub::Notifications.recipients(session.unit, author_id: session.author_id),
      event: event,
      dedupe_key: "#{event}:#{session.id}:v#{version}",
      notifiable: session,
      message: UnitHub::Notifications.session_changed_message(session, change),
      link: UnitHub::Notifications.session_link(session)
    )
  end
end
