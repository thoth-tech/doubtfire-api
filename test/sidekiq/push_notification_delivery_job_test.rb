# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class PushNotificationDeliveryJobTest < ActiveSupport::TestCase
  VAPID_PUBLIC = 'BOs-KbIoHK7gUIX3i2_uEuDoouj-GKxB-mY9CRmLNmd4Wn-SSl254E1g6jR1ukL3e37p8uCpaMjOvfAB0BwzvSI='
  VAPID_PRIVATE = '_NFIWSUTdCdLJJFh87pf4ekQLmNYqsweZ4288NpVZaY='
  ENDPOINT = 'https://fcm.googleapis.com/fcm/send/job-retry-browser'

  setup do
    PushNotificationDeliveryJob.clear
  end

  def test_perform_delivers_the_reloaded_notification
    notification = FactoryBot.create(:notification, event: 'general')
    delivered = nil

    PushNotificationService.stub(:deliver, ->(record) { delivered = record }) do
      PushNotificationDeliveryJob.new.perform(notification.id)
    end

    assert_equal notification, delivered
  end

  def test_missing_notification_is_raised_so_a_pre_commit_race_is_retried
    PushNotificationService.stub(:deliver, ->(_record) { flunk 'missing row must not be delivered' }) do
      assert_raises(ActiveRecord::RecordNotFound) do
        PushNotificationDeliveryJob.new.perform(-1)
      end
    end
  end

  def test_delivery_failure_is_raised_so_sidekiq_can_retry
    notification = FactoryBot.create(:notification, event: 'general')
    failure = ->(_record) { raise 'push provider unavailable' }

    PushNotificationService.stub(:deliver, failure) do
      error = assert_raises(RuntimeError) do
        PushNotificationDeliveryJob.new.perform(notification.id)
      end
      assert_equal 'push provider unavailable', error.message
    end
  end

  def test_no_delivery_when_the_preference_was_turned_off_after_queueing
    user = FactoryBot.create(:user, receive_feedback_notifications: true)
    notification = FactoryBot.create(
      :notification,
      :feedback,
      user: user,
      event: 'task_comment_created',
      message: 'Queued while the category was still on.'
    )

    # retry: 3 means the job can run well after it was queued.
    user.update!(receive_feedback_notifications: false)

    PushNotificationService.stub(:deliver, ->(_record) { flunk 'push must not be delivered after the category is off' }) do
      PushNotificationDeliveryJob.new.perform(notification.id)
    end
  end

  def test_a_type_without_a_preference_is_still_delivered
    user = FactoryBot.create(
      :user,
      receive_task_notifications: false,
      receive_feedback_notifications: false,
      receive_portfolio_notifications: false
    )
    notification = FactoryBot.create(
      :notification,
      user: user,
      event: 'general',
      message: 'General notices ignore the category toggles.'
    )
    delivered = nil

    PushNotificationService.stub(:deliver, ->(record) { delivered = record }) do
      PushNotificationDeliveryJob.new.perform(notification.id)
    end

    assert_equal notification, delivered
  end

  def test_real_provider_failure_reaches_the_sidekiq_retry_boundary
    notification = FactoryBot.create(:notification, event: 'general')
    FactoryBot.create(
      :push_subscription,
      user: notification.user,
      endpoint: ENDPOINT
    )
    stub_request(:post, ENDPOINT).to_return(status: 503)

    with_vapid_keys do
      assert_raises(PushNotificationService::DeliveryError) do
        PushNotificationDeliveryJob.new.perform(notification.id)
      end
    end
  end

  def test_async_payload_contains_only_the_notification_id
    notification = FactoryBot.create(:notification, event: 'general')
    jid = PushNotificationDeliveryJob.perform_async(notification.id)
    job = PushNotificationDeliveryJob.jobs.find do |candidate|
      candidate['jid'] == jid
    end

    assert_not_nil job
    assert_equal 'PushNotificationDeliveryJob', job['class']
    assert_equal 'notifications', job['queue']
    assert_equal [notification.id], job['args']
    assert_equal 'notifications', PushNotificationDeliveryJob.get_sidekiq_options['queue'].to_s
    assert_equal 3, PushNotificationDeliveryJob.get_sidekiq_options['retry']
  end

  private

  def with_vapid_keys
    names = %w[DOUBTFIRE_VAPID_PUBLIC_KEY DOUBTFIRE_VAPID_PRIVATE_KEY]
    previous = names.index_with { |name| ENV.fetch(name, nil) }
    ENV['DOUBTFIRE_VAPID_PUBLIC_KEY'] = VAPID_PUBLIC
    ENV['DOUBTFIRE_VAPID_PRIVATE_KEY'] = VAPID_PRIVATE
    yield
  ensure
    previous.each do |name, value|
      value.nil? ? ENV.delete(name) : ENV[name] = value
    end
  end
end
