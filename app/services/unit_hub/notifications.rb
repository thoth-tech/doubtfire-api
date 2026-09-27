# frozen_string_literal: true

require 'digest'

module UnitHub
  # Notifications about Unit Hub announcements and learning sessions.
  #
  # The models call the *_committed methods from after_commit, which decide
  # whether a save is worth telling anyone about and queue a job with only ids
  # and a version. The jobs call fan_out, which walks the unit's recipients in
  # batches and raises each notification through NotificationService, so the
  # category preference, email and push all behave like every other event.
  #
  # Every notification carries a dedupe key made of the event, the record and a
  # version of it, which the unique index scopes to the recipient. A retried or
  # duplicated job finds the row that is already there instead of sending again.
  module Notifications
    TYPE = 'unit_hub'

    ANNOUNCEMENT_PUBLISHED = 'unit_announcement_published'
    ANNOUNCEMENT_UPDATED = 'unit_announcement_updated'
    SESSION_CHANGED = 'unit_session_changed'
    SESSION_STARTING_SOON = 'unit_session_starting_soon'
    EVENTS = [ANNOUNCEMENT_PUBLISHED, ANNOUNCEMENT_UPDATED, SESSION_CHANGED, SESSION_STARTING_SOON].freeze

    BATCH_SIZE = 200

    # At most one update notification per announcement per recipient in this
    # window. A publish inside the window counts, so fixing a line straight
    # after posting does not send a second notification.
    UPDATE_DEBOUNCE = 30.minutes

    # How long before a session its reminder goes out.
    REMINDER_LEAD = 30.minutes

    # An announcement created with a publication time older than this is an
    # import or a backfill, not news, so it does not raise a publish.
    BACKFILL_AGE = 1.day

    SESSION_SCHEDULE_FIELDS = %w[start_at end_at timezone recurrence recurrence_until location join_url].freeze

    # A one letter fix in a word of four or more letters is a typo. Anything
    # else that changes the words, or any change to a number, is not.
    TYPO_DISTANCE = 2

    module_function

    # ---- deciding what a save means ------------------------------------------

    def announcement_committed(record, created:)
      now = Time.current
      return unless announcement_source_allowed?(record)

      if created
        return if record.published_at.nil?
        return if record.published_at < record.created_at - BACKFILL_AGE

        return queue_publish(record, now)
      end

      changes = record.saved_changes
      was_visible = visible_with?(
        changes.key?('published_at') ? changes['published_at'].first : record.published_at,
        changes.key?('expires_at') ? changes['expires_at'].first : record.expires_at,
        now
      )

      unless was_visible
        return unless changes.keys.intersect?(%w[published_at expires_at])
        return if record.published_at.nil? || (record.expires_at && record.expires_at <= now)

        return queue_publish(record, now)
      end
      return unless visible_with?(record.published_at, record.expires_at, now)

      # Pinning a visible announcement puts it back in front of people, so it is
      # raised as a publish with its own version. Unpinning is not news.
      if changes.key?('pinned') && record.pinned
        UnitAnnouncementNotificationJob.perform_async(record.id, ANNOUNCEMENT_PUBLISHED, "pinned-#{record.updated_at.to_i}")
        return
      end

      old_title = changes.key?('title') ? changes['title'].first : record.title
      old_body = changes.key?('body') ? changes['body'].first : record.body
      return unless meaningful_edit?(old_title, record.title) || meaningful_edit?(old_body, record.body)

      UnitAnnouncementNotificationJob.perform_async(record.id, ANNOUNCEMENT_UPDATED, nil)
    end

    def session_committed(record)
      changes = record.saved_changes
      published_before = changes.key?('published') ? changes['published'].first : record.published
      return unless record.published && published_before

      cancelled_now = changes.key?('cancelled') && record.cancelled
      restored = changes.key?('cancelled') && !record.cancelled
      schedule_changed = changes.keys.intersect?(SESSION_SCHEDULE_FIELDS)
      return unless cancelled_now || (!record.cancelled && (schedule_changed || restored))
      return if next_occurrence(record, Time.current).nil?

      UnitSessionNotificationJob.perform_async(record.id, record.lock_version, cancelled_now ? 'cancelled' : 'changed')
    end

    def queue_publish(record, now)
      version = "published-#{record.published_at.to_i}"
      if record.published_at > now
        UnitAnnouncementNotificationJob.perform_at(record.published_at, record.id, ANNOUNCEMENT_PUBLISHED, version)
      else
        UnitAnnouncementNotificationJob.perform_async(record.id, ANNOUNCEMENT_PUBLISHED, version)
      end
    end

    def visible_with?(published_at, expires_at, at)
      published_at.present? && published_at <= at && (expires_at.nil? || expires_at > at)
    end

    def announcement_source_allowed?(record)
      UnitAnnouncement.allowed_sources.exists?(id: record.id)
    end

    # Whether an edit changes what an announcement says, rather than fixing how
    # it is spelled. Case, spacing and punctuation never count. A number always
    # counts, because a changed date, time or room is the edit people need to
    # hear about. One word swapped for a near spelling, or a doubled word taken
    # out, is a typo. Any other change to the words counts.
    def meaningful_edit?(before, after)
      old_words = words(before)
      new_words = words(after)
      removed = multiset_difference(old_words, new_words)
      added = multiset_difference(new_words, old_words)
      changed = removed + added

      return false if changed.empty?
      return true if changed.any? { |word| word.match?(/\d/) }

      if removed.length == 1 && added.length == 1
        return true if [removed.first.length, added.first.length].min < 4

        return DidYouMean::Levenshtein.distance(removed.first, added.first) > TYPO_DISTANCE
      end

      return !(old_words.include?(changed.first) && new_words.include?(changed.first)) if changed.length == 1

      true
    end

    def words(text)
      text.to_s.downcase.scan(/[[:alnum:]]+/)
    end

    def multiset_difference(left, right)
      remaining = right.tally
      left.each_with_object([]) do |word, result|
        if remaining[word].to_i.positive?
          remaining[word] -= 1
        else
          result << word
        end
      end
    end

    # ---- who hears about it --------------------------------------------------

    # Enrolled students and teaching staff of an active unit, with the Unit Hub
    # category on, never the person who wrote the thing.
    def recipients(unit, author_id: nil)
      return User.none unless unit&.active

      student_ids = Project.where(unit_id: unit.id, enrolled: true).select(:user_id)
      staff_ids = UnitRole.where(unit_id: unit.id, role_id: [Role.tutor.id, Role.convenor.id]).select(:user_id)
      scope = User.where(id: student_ids).or(User.where(id: staff_ids)).where(receive_unit_hub_notifications: true)
      author_id ? scope.where.not(id: author_id) : scope
    end

    # Raise one notification per recipient, a batch at a time.
    #
    # skip - called with a batch of user ids, returns the ids to leave out on
    #        top of the ones that already hold this dedupe key.
    # Failures are collected and raised at the end so Sidekiq retries the whole
    # fan-out, which the dedupe key makes safe.
    def fan_out(scope:, event:, dedupe_key:, notifiable:, message:, link:, skip: nil)
      failed = []
      scope.find_in_batches(batch_size: BATCH_SIZE) do |batch|
        ids = batch.map(&:id)
        skipped = Notification.where(user_id: ids, dedupe_key: dedupe_key).pluck(:user_id)
        skipped.concat(skip.call(ids)) if skip
        skipped = skipped.to_set

        batch.each do |user|
          next if skipped.include?(user.id)

          NotificationService.notify(
            user: user, type: TYPE, event: event, message: message,
            link: link, dedupe_key: dedupe_key, notifiable: notifiable
          )
        rescue StandardError => e
          failed << user.id
          Rails.logger.error("Failed #{event} notification for User #{user.id}: #{e.class}")
        end
      end

      raise "#{event} notifications failed for users: #{failed.join(', ')}" if failed.any?
    end

    # ---- what it says --------------------------------------------------------

    def announcement_link(record)
      "/unit-hub?unit=#{record.unit_id}&announcement=#{record.id}"
    end

    def session_link(record)
      "/unit-hub?unit=#{record.unit_id}&session=#{record.id}"
    end

    def announcement_message(record, event)
      prefix =
        if event == ANNOUNCEMENT_UPDATED
          'Announcement updated'
        elsif record.pinned
          'Pinned announcement'
        else
          'New announcement'
        end
      "#{prefix} in #{record.unit.code}: #{record.title}".truncate(500)
    end

    def session_changed_message(record, change, at: Time.current)
      unit_code = record.unit.code
      if change == 'cancelled'
        return "The weekly #{record.title} sessions in #{unit_code} are cancelled.".truncate(500) if record.recurrence == 'weekly'

        occurrence = next_occurrence(record, at)
        when_text = occurrence ? " on #{format_time(occurrence[:start_at], record.timezone)}" : ''
        return "#{record.title} in #{unit_code}#{when_text} is cancelled.".truncate(500)
      end

      "#{record.title} in #{unit_code} has changed. #{where_and_when(record, at)}".truncate(500)
    end

    def session_starting_soon_message(record, start_at)
      place = session_place(record)
      "#{record.title} in #{record.unit.code} starts at #{format_clock(start_at, record.timezone)}#{" (#{place})" if place}.".truncate(500)
    end

    def where_and_when(record, at)
      occurrence = next_occurrence(record, at)
      return 'Open the Unit Hub for the details.' if occurrence.nil?

      cadence = record.recurrence == 'weekly' ? 'Next session' : 'Now'
      place = session_place(record)
      "#{cadence}: #{format_time(occurrence[:start_at], record.timezone)}#{", #{place}" if place}."
    end

    def session_place(record)
      return record.location if record.location.present?

      'online' if record.join_url.present?
    end

    def next_occurrence(record, at)
      record.occurrences(from: at, to: at + 7.months).find { |occurrence| occurrence[:end_at] >= at }
    end

    def format_time(time, zone)
      local = time.in_time_zone(zone)
      "#{local.strftime('%a %-d %b')} at #{format_clock(local, zone)}"
    end

    def format_clock(time, zone)
      local = time.in_time_zone(zone)
      "#{local.strftime('%-l:%M%P')} #{local.zone}"
    end

    # The details an email shows for a session, in the session's own zone.
    def session_details(record, at:)
      occurrence = next_occurrence(record, at)
      details = { 'Unit' => "#{record.unit.code} #{record.unit.name}", 'Session' => record.title }
      if occurrence
        local_start = occurrence[:start_at].in_time_zone(record.timezone)
        local_end = occurrence[:end_at].in_time_zone(record.timezone)
        details['When'] = "#{format_time(local_start, record.timezone)} to #{local_end.strftime('%-l:%M%P')}"
        details['Repeats'] = "Weekly until #{record.recurrence_until.strftime('%-d %b %Y')}" if record.recurrence == 'weekly' && record.recurrence_until
      end
      details['Where'] = record.location if record.location.present?
      details['Online'] = 'A join link is on the Unit Hub' if record.join_url.present? && !record.cancelled
      details['Status'] = 'Cancelled' if record.cancelled
      details
    end

    def announcement_version(record)
      Digest::SHA256.hexdigest([record.title, record.body].join(" "))[0, 16]
    end
  end
end
