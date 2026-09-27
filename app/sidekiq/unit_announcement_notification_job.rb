# frozen_string_literal: true

# Tell a unit about an announcement that was published, pinned or meaningfully
# edited. Queued by UnitHub::Notifications.announcement_committed after the save
# commits, with only the announcement id, the event and a version.
class UnitAnnouncementNotificationJob
  include Sidekiq::Job

  # How early a scheduled publish may run before it retries instead of giving
  # up. Anything further out was rescheduled and has its own job.
  EARLY_TOLERANCE = 5.minutes

  # A publish or pin is locked on its version, so a rescheduled publication time
  # gets a job of its own. An update is locked on the announcement alone: while
  # one update job is waiting or running, a second edit adds nothing, because
  # the job reads the announcement as it is when it runs and the debounce would
  # hold a second notification back anyway.
  sidekiq_options queue: :notifications,
                  lock: :until_executed,
                  lock_args_method: lambda { |args|
                    args[1] == UnitHub::Notifications::ANNOUNCEMENT_UPDATED ? args.first(2) : args
                  },
                  on_conflict: :reject,
                  retry: 3

  def perform(announcement_id, event, version)
    announcement = UnitAnnouncement.find_by(id: announcement_id)
    return if announcement.nil?

    now = Time.current
    if event == UnitHub::Notifications::ANNOUNCEMENT_PUBLISHED && version.to_s.start_with?('published-')
      return unless announcement.published_at.to_i.to_s == version.delete_prefix('published-')
      raise 'Announcement is not published yet, retrying' if announcement.published_at > now && announcement.published_at <= now + EARLY_TOLERANCE
    end
    return if event == UnitHub::Notifications::ANNOUNCEMENT_PUBLISHED && version.to_s.start_with?('pinned-') && !announcement.pinned
    return unless UnitAnnouncement.visible_at(now).exists?(id: announcement.id)

    event == UnitHub::Notifications::ANNOUNCEMENT_UPDATED ? notify_updated(announcement, now) : notify_published(announcement, version)
  end

  private

  def notify_published(announcement, version)
    UnitHub::Notifications.fan_out(
      scope: UnitHub::Notifications.recipients(announcement.unit, author_id: announcement.author_id),
      event: UnitHub::Notifications::ANNOUNCEMENT_PUBLISHED,
      dedupe_key: "#{UnitHub::Notifications::ANNOUNCEMENT_PUBLISHED}:#{announcement.id}:#{version}",
      notifiable: announcement,
      message: UnitHub::Notifications.announcement_message(announcement, UnitHub::Notifications::ANNOUNCEMENT_PUBLISHED),
      link: UnitHub::Notifications.announcement_link(announcement)
    )
  end

  def notify_updated(announcement, now)
    event = UnitHub::Notifications::ANNOUNCEMENT_UPDATED
    UnitHub::Notifications.fan_out(
      scope: UnitHub::Notifications.recipients(announcement.unit, author_id: announcement.author_id),
      event: event,
      dedupe_key: "#{event}:#{announcement.id}:#{UnitHub::Notifications.announcement_version(announcement)}",
      notifiable: announcement,
      message: UnitHub::Notifications.announcement_message(announcement, event),
      link: UnitHub::Notifications.announcement_link(announcement),
      # Anyone told about this announcement within the debounce window, by a
      # publish or an earlier update, is left alone this time.
      skip: lambda { |user_ids|
        Notification.where(
          user_id: user_ids,
          notifiable: announcement,
          event: [UnitHub::Notifications::ANNOUNCEMENT_PUBLISHED, event]
        ).where('created_at > ?', now - UnitHub::Notifications::UPDATE_DEBOUNCE).distinct.pluck(:user_id)
      }
    )
  end
end
