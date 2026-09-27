# frozen_string_literal: true

require 'test_helper'
require 'timeout'

class NotificationDeliveryPolicyConcurrencyTest < ActiveSupport::TestCase
  # Each producer must commit on its own connection, as real request/job
  # transactions do. A fixture transaction would hide the recipient from them.
  self.use_transactional_tests = false

  setup do
    skip 'Requires MySQL/MariaDB repeatable-read transactions' unless ActiveRecord::Base.connection.adapter_name == 'Mysql2'

    @previous_limits = %w[
      DOUBTFIRE_NOTIFICATION_RECIPIENT_LIMIT
      DOUBTFIRE_NOTIFICATION_RECIPIENT_WINDOW_SECONDS
    ].index_with { |name| ENV.fetch(name, nil) }
    ENV['DOUBTFIRE_NOTIFICATION_RECIPIENT_LIMIT'] = '1'
    ENV['DOUBTFIRE_NOTIFICATION_RECIPIENT_WINDOW_SECONDS'] = '3600'

    nonce = SecureRandom.hex(8)
    @recipient = FactoryBot.create(:user, username: "quota-race-#{nonce}",
                                          email: "quota-race-#{nonce}@example.invalid")
    NotificationEmailJob.clear
    PushNotificationDeliveryJob.clear
  end

  teardown do
    @recipient&.destroy!
    @previous_limits&.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
  end

  def test_outer_transaction_snapshot_cannot_hide_a_committed_quota_reservation
    first, second = reserve_after_older_snapshot

    assert_equal 0, @snapshot_notification_count
    assert_equal 'pending', first.reload.email_delivery_state
    assert_equal 'throttled', second.reload.email_delivery_state
    assert_equal 2, Notification.where(user_id: @recipient.id).count
    assert_equal([[first.id]], NotificationEmailJob.jobs.map { |job| job['args'] })
    assert_equal([[first.id]], PushNotificationDeliveryJob.jobs.map { |job| job['args'] })
  end

  def test_duplicate_lookup_sees_the_winner_despite_an_older_transaction_snapshot
    first, second = reserve_after_older_snapshot(dedupe_key: 'concurrent-event')

    assert_equal 0, @snapshot_notification_count
    assert_equal first.id, second.id
    assert_equal 'pending', second.reload.email_delivery_state
    assert_equal 1, Notification.where(user_id: @recipient.id).count
    assert_equal([[first.id]], NotificationEmailJob.jobs.map { |job| job['args'] })
    assert_equal([[first.id]], PushNotificationDeliveryJob.jobs.map { |job| job['args'] })
  end

  def test_duplicate_with_a_failed_push_handoff_retries_after_outer_commit
    first, second = reserve_after_older_snapshot(dedupe_key: 'retry-push', fail_first_push: true)

    assert_equal first.id, second.id
    assert_not_nil second.reload.delivered_at
    assert_equal [[first.id]], (NotificationEmailJob.jobs.map { |job| job['args'] })
    assert_equal [[first.id]], (PushNotificationDeliveryJob.jobs.map { |job| job['args'] })
  end

  def test_recipient_update_does_not_abort_a_reservation_in_an_older_snapshot
    snapshot_established = Queue.new
    recipient_update_committed = Queue.new
    producers = []
    original_first_name = @recipient.first_name
    snapshot_first_name = nil

    producers << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Timeout.timeout(15) { snapshot_established.pop }
        User.find(@recipient.id).update!(first_name: 'Changed while reserving')
        recipient_update_committed << true
      end
    end

    producers << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        ActiveRecord::Base.transaction(isolation: :repeatable_read) do
          # A surrounding assessment can already have a snapshot when a
          # student changes their profile before the notification is reserved.
          recipient = User.find(@recipient.id)
          snapshot_first_name = recipient.first_name
          snapshot_established << true
          Timeout.timeout(15) { recipient_update_committed.pop }
          NotificationService.reserve(user: recipient, type: 'extension',
                                      event: 'resubmission_deadline_changed',
                                      message: 'Concurrent recipient update regression')
        end
      end
    end

    notification = Timeout.timeout(20) { producers.map(&:value).last }
    assert_equal original_first_name, snapshot_first_name
    assert_equal 'Changed while reserving', @recipient.reload.first_name
    assert_equal 'pending', notification.reload.email_delivery_state
    assert_equal 1, Notification.where(user_id: @recipient.id).count
    assert_equal [[notification.id]], (NotificationEmailJob.jobs.map { |job| job['args'] })
    assert_empty PushNotificationDeliveryJob.jobs
  ensure
    producers&.each { |producer| producer.kill if producer.alive? }
    producers&.each(&:join)
  end

  def test_reservation_restores_mariadb_snapshot_setting_after_success_and_failure
    connection = ActiveRecord::Base.connection
    skip 'Requires MariaDB snapshot isolation setting' unless connection.mariadb? &&
                                                              connection.select_rows("SHOW VARIABLES LIKE 'innodb_snapshot_isolation'").any?

    original = connection.select_value('SELECT @@SESSION.innodb_snapshot_isolation').to_i
    [0, 1].each do |setting|
      connection.execute("SET SESSION innodb_snapshot_isolation = #{setting}")
      NotificationService.reserve(user: @recipient, type: 'general', event: 'setting_restoration', message: 'Reserved')
      assert_equal setting, connection.select_value('SELECT @@SESSION.innodb_snapshot_isolation').to_i

      assert_raises(ActiveRecord::RecordInvalid) do
        NotificationService.reserve(user: @recipient, type: 'general', event: 'invalid_reservation', message: nil)
      end
      assert_equal setting, connection.select_value('SELECT @@SESSION.innodb_snapshot_isolation').to_i
    end
  ensure
    connection.execute("SET SESSION innodb_snapshot_isolation = #{original}") unless original.nil?
  end

  def test_outer_rollback_removes_reservation_without_queuing_a_channel
    assert_no_difference 'Notification.count' do
      User.transaction do
        notification = NotificationService.reserve(user: @recipient, type: 'general', event: 'rolled_back', message: 'Reserved')
        assert notification.persisted?
        raise ActiveRecord::Rollback
      end
    end
    assert_empty NotificationEmailJob.jobs
    assert_empty PushNotificationDeliveryJob.jobs
  end

  private

  def reserve_after_older_snapshot(dedupe_key: nil, fail_first_push: false)
    snapshot_established = Queue.new
    first_reservation_committed = Queue.new
    producers = []

    producers << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Timeout.timeout(15) { snapshot_established.pop }
        notification = if fail_first_push
                         PushNotificationDeliveryJob.stub(:perform_async, false) do
                           raise_notification('first_reservation', dedupe_key)
                         end
                       else
                         raise_notification('first_reservation', dedupe_key)
                       end
        # notify has returned from its transaction, so the first row and both
        # channel hand-offs exist before the older transaction resumes.
        first_reservation_committed << true
        notification
      end
    end

    producers << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        ActiveRecord::Base.transaction(isolation: :repeatable_read) do
          # An ordinary read in a surrounding workflow (for example the
          # project's eligibility reload) establishes this same older snapshot.
          @snapshot_notification_count = Notification.where(user_id: @recipient.id).count
          snapshot_established << true
          Timeout.timeout(15) { first_reservation_committed.pop }
          raise_notification('second_reservation', dedupe_key)
        end
      end
    end

    Timeout.timeout(20) { producers.map(&:value) }
  ensure
    producers&.each { |producer| producer.kill if producer.alive? }
    producers&.each(&:join)
  end

  def raise_notification(event, dedupe_key)
    NotificationService.notify(user: User.find(@recipient.id), type: 'general', event: event,
                               message: 'Concurrent quota regression', dedupe_key: dedupe_key)
  end
end
