require 'test_helper'
# test_helper does not pull this in, and Object#stub comes from it. Without it
# test_both_timeouts_are_passed_to_the_gem errors with "undefined method 'stub'
# for module WebPush", which it has done since it was written.
require 'minitest/mock'

# MN-F02: the push channel actually sends.
#
# These tests go through the real web-push gem and stub the HTTP call to the
# push service, rather than stubbing WebPush itself. That is deliberate: the
# part most likely to be wired up wrong is the gem call and the payload, and a
# stub of WebPush.payload_send would prove neither.
class PushNotificationServiceTest < ActiveSupport::TestCase
  # A throwaway VAPID pair, generated for these tests. The matching browser key
  # pair lives in the push_subscription factory, which is where the real
  # prime256v1 public key the gem needs to encrypt against now comes from.
  VAPID_PUBLIC = 'BOs-KbIoHK7gUIX3i2_uEuDoouj-GKxB-mY9CRmLNmd4Wn-SSl254E1g6jR1ukL3e37p8uCpaMjOvfAB0BwzvSI='.freeze
  VAPID_PRIVATE = '_NFIWSUTdCdLJJFh87pf4ekQLmNYqsweZ4288NpVZaY='.freeze

  # Fixed rather than sequenced, because every test here has to stub the exact
  # URL the gem will post to.
  ENDPOINT = 'https://fcm.googleapis.com/fcm/send/test-browser'.freeze

  setup do
    @user = FactoryBot.create(:user, :student)
    @notification = Notification.create!(
      user: @user,
      notification_type: 'feedback',
      event: 'task_comment_created',
      message: 'Andrew Cain commented on 1.1P in COS10001.',
      link: '/projects/2/dashboard/1.1P'
    )
  end

  # Set the keys for the block and put the environment back exactly as it was.
  #
  # Restoring rather than deleting matters: the development container now has
  # real values in its environment, so a test that deleted them would leave the
  # process different from how it found it, and a test that assumed they were
  # absent to begin with would pass in CI and fail on a developer's machine.
  def with_env(values)
    previous = values.keys.index_with { |key| ENV.fetch(key, nil) }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def with_keys(&)
    with_env({ 'DOUBTFIRE_VAPID_PUBLIC_KEY' => VAPID_PUBLIC, 'DOUBTFIRE_VAPID_PRIVATE_KEY' => VAPID_PRIVATE }, &)
  end

  def without_keys(&)
    with_env({ 'DOUBTFIRE_VAPID_PUBLIC_KEY' => nil, 'DOUBTFIRE_VAPID_PRIVATE_KEY' => nil }, &)
  end

  def create_subscription(endpoint: ENDPOINT)
    FactoryBot.create(:push_subscription, user: @user, endpoint: endpoint)
  end

  # Read out of the built payload rather than off tag_for, so these tests fail
  # if the tag stops reaching the part that is actually sent.
  def tag_for(notification)
    JSON.parse(PushNotificationService.payload_for(notification))['notification']['tag']
  end

  def click_data(notification = @notification)
    JSON.parse(PushNotificationService.payload_for(notification)).dig('notification', 'data')
  end

  def test_nothing_is_sent_when_the_vapid_keys_are_missing
    create_subscription

    # No WebMock stub is registered, so any outbound request would raise.
    without_keys do
      assert_not PushNotificationService.configured?
      assert_nothing_raised { PushNotificationService.deliver(@notification) }
    end
  end

  def test_a_notification_is_pushed_to_the_subscribed_browser
    create_subscription
    request = stub_request(:post, ENDPOINT).to_return(status: 201)

    with_keys { PushNotificationService.deliver(@notification) }

    assert_requested request
  end

  def test_every_subscribed_browser_is_pushed_to
    create_subscription(endpoint: "#{ENDPOINT}-one")
    create_subscription(endpoint: "#{ENDPOINT}-two")

    first = stub_request(:post, "#{ENDPOINT}-one").to_return(status: 201)
    second = stub_request(:post, "#{ENDPOINT}-two").to_return(status: 201)

    with_keys { PushNotificationService.deliver(@notification) }

    assert_requested first
    assert_requested second
  end

  def test_nothing_is_sent_when_the_user_has_no_browsers_registered
    with_keys { assert_nothing_raised { PushNotificationService.deliver(@notification) } }
  end

  def test_a_gone_subscription_is_deleted
    create_subscription
    stub_request(:post, ENDPOINT).to_return(status: 410)

    assert_difference 'PushSubscription.count', -1 do
      with_keys { PushNotificationService.deliver(@notification) }
    end
  end

  def test_a_not_found_subscription_is_deleted
    create_subscription
    stub_request(:post, ENDPOINT).to_return(status: 404)

    assert_difference 'PushSubscription.count', -1 do
      with_keys { PushNotificationService.deliver(@notification) }
    end
  end

  # A rate limit or an outage is temporary. Deleting on those would silently
  # unsubscribe people the first time a push service had a bad day.
  def test_a_temporary_push_service_failure_is_raised_for_retry_and_keeps_the_subscription
    create_subscription
    stub_request(:post, ENDPOINT).to_return(status: 429)

    assert_no_difference 'PushSubscription.count' do
      with_keys do
        assert_raises(PushNotificationService::DeliveryError) do
          PushNotificationService.deliver(@notification)
        end
      end
    end
  end

  def test_a_temporary_failure_does_not_stop_the_other_browsers
    failing_endpoint = "#{ENDPOINT}-unavailable"
    healthy_endpoint = "#{ENDPOINT}-healthy"
    create_subscription(endpoint: failing_endpoint)
    create_subscription(endpoint: healthy_endpoint)

    stub_request(:post, failing_endpoint).to_return(status: 503)
    healthy = stub_request(:post, healthy_endpoint).to_return(status: 201)

    with_keys do
      assert_raises(PushNotificationService::DeliveryError) do
        PushNotificationService.deliver(@notification)
      end
    end

    assert_requested healthy
    assert_equal 2, @user.push_subscriptions.reload.count
  end

  def test_one_dead_browser_does_not_stop_the_others
    create_subscription(endpoint: "#{ENDPOINT}-dead")
    create_subscription(endpoint: "#{ENDPOINT}-alive")

    stub_request(:post, "#{ENDPOINT}-dead").to_return(status: 410)
    alive = stub_request(:post, "#{ENDPOINT}-alive").to_return(status: 201)

    with_keys { PushNotificationService.deliver(@notification) }

    assert_requested alive
    assert_equal ["#{ENDPOINT}-alive"], @user.push_subscriptions.reload.map(&:endpoint)
  end

  # Angular's ngsw-worker.js only displays a push if the payload has a top level
  # "notification" key. Anything else needs a hand written service worker.
  def test_the_payload_has_the_shape_angulars_service_worker_expects
    payload = JSON.parse(PushNotificationService.payload_for(@notification))

    assert payload.key?('notification'), 'ngsw-worker.js will ignore a payload without this key'

    body = payload['notification']
    assert_equal '/assets/icons/android-chrome-192x192.png', body['icon']
    assert_equal '/assets/icons/android-chrome-192x192.png', body['badge']

    assert_equal 'Andrew Cain commented on 1.1P in COS10001.', body['body']
    assert_equal '/projects/2/dashboard/1.1P', body.dig('data', 'link')
    assert_equal @notification.id, body.dig('data', 'notification_id')
    assert_equal 'focusLastFocusedOrOpen',
                 body.dig('data', 'onActionClick', 'default', 'operation')
    assert_equal '/projects/2/dashboard/1.1P',
                 body.dig('data', 'onActionClick', 'default', 'url')
    assert_not_nil body['title']
  end

  def test_v2_events_with_sensitive_detail_use_reviewed_lock_screen_copy
    sensitive_canary = 'PRIVATE-NAME-AND-SCHEDULE-7429'
    expected_bodies = {
      'tutorial_changed' => 'Your tutorial details changed.',
      'group_membership_changed' => 'Your group membership changed.',
      'task_submitted' => 'A task is ready for marking.',
      'portfolio_received' => 'Your portfolio submission was received.'
    }

    expected_bodies.each do |event, expected_body|
      notification = Notification.create!(
        user: @user,
        notification_type: 'general',
        event: event,
        message: "#{sensitive_canary} appeared in the rich channel copy.",
        link: '/notifications'
      )

      body = JSON.parse(PushNotificationService.payload_for(notification))
                 .dig('notification', 'body')

      assert_equal expected_body, body, event
      assert_not_includes body, sensitive_canary, event
    end
  end

  def test_click_payload_preserves_every_approved_route_family
    routes = [
      '/notifications',
      '/projects/2/dashboard',
      '/projects/2/groups',
      '/projects/2/dashboard/1.1P',
      '/projects/2/dashboard/1.1P/feedback',
      '/projects/2/dashboard/T1.1',
      '/projects/2/dashboard/HD1.2',
      '/projects/2/dashboard/10.1H',
      '/projects/2/dashboard/A15',
      '/projects/2/dashboard/TASK1',
      '/projects/2/dashboard/P-2.21',
      '/projects/2/dashboard/D-9.568',
      '/projects/2/dashboard/C-4.602'
    ]

    routes.each do |route|
      @notification.link = route
      data = click_data

      assert_equal route, data['link']
      assert_equal route, data.dig('onActionClick', 'default', 'url')
      assert_equal 'focusLastFocusedOrOpen',
                   data.dig('onActionClick', 'default', 'operation')
    end
  end

  def test_click_payload_falls_back_for_missing_malformed_external_and_encoded_links
    invalid_links = [
      nil,
      '',
      ' ',
      'http://example.test/projects/2/dashboard',
      'https://example.test/projects/2/dashboard',
      'mailto:student@example.test',
      'javascript:alert(1)',
      'data:text/html,unsafe',
      'file:///etc/passwd',
      '//example.test/projects/2/dashboard',
      '\\example.test\\projects\\2',
      '/projects/2\\dashboard',
      '/%2f%2fexample.test',
      '/%5cexample.test',
      '/projects/2/dashboard/%31.1P',
      '/projects/2/dashboard/1.1P%3ftoken%3dsecret',
      '/%252f%252fexample.test',
      '/projects/2/dashboard/%',
      '/projects/0/dashboard',
      '/projects/2/dashboard/',
      '/projects/2/dashboard/1.1P/extra',
      '/projects/2/dashboard/1.1P/feedback/extra',
      '/projects/2/dashboard/1.1P?token=secret',
      '/projects/2/dashboard/1.1P#feedback',
      "/projects/2/dashboard/#{'A1' * 20}",
      '/units/2',
      '/home'
    ]

    invalid_links.each do |link|
      @notification.link = link
      data = click_data

      assert_equal '/notifications', data['link'], "expected fallback for #{link.inspect}"
      assert_equal '/notifications', data.dig('onActionClick', 'default', 'url')
    end
  end

  def test_an_unsafe_link_is_not_copied_into_the_push_tag
    @notification.link = 'https://example.test/unsafe'

    tag = tag_for(@notification)
    assert_equal "notification-#{@notification.id}", tag
    assert_not_includes tag, 'example.test'
  end

  def test_click_payload_preserves_bounded_task_segments_without_guessing_their_format
    routes = [
      '/projects/2/dashboard/85',
      '/projects/2/dashboard/Alice1',
      '/projects/2/dashboard/BOB1',
      '/projects/2/dashboard/1.1ALICE',
      '/projects/2/dashboard/1.1BOB',
      '/projects/2/dashboard/feedback1',
      '/projects/2/dashboard/token123',
      '/projects/2/dashboard/mark85'
    ]

    routes.each do |route|
      @notification.link = route
      data = click_data

      assert_equal route, data['link']
      assert_equal route, data.dig('onActionClick', 'default', 'url')
    end
  end

  def test_two_notifications_about_the_same_thing_share_a_tag
    second = Notification.create!(
      user: @user,
      notification_type: @notification.notification_type,
      event: @notification.event,
      message: 'Andrew Cain commented on 1.1P in COS10001.',
      link: @notification.link
    )

    assert_equal tag_for(@notification), tag_for(second)
  end

  # The half that is easy to get wrong in the other direction. A tag shared by
  # unrelated notifications does not tidy anything up, it hides one behind
  # another and the user never sees it.
  def test_notifications_about_different_things_do_not_share_a_tag
    elsewhere = Notification.create!(
      user: @user,
      notification_type: @notification.notification_type,
      event: @notification.event,
      message: 'Andrew Cain commented on 2.1P in COS10001.',
      link: '/projects/2/dashboard/2.1P'
    )

    assert_not_equal tag_for(@notification), tag_for(elsewhere)
  end

  # The tag names the conversation, so it cannot contain anything that changes
  # between messages in it. Using the notification id would be unique every time
  # and would collapse nothing at all, which is the whole ticket undone.
  def test_the_tag_does_not_change_between_notifications_in_a_burst
    tags = 3.times.map do |index|
      burst = Notification.create!(
        user: @user,
        notification_type: @notification.notification_type,
        event: @notification.event,
        message: "Andrew Cain commented on 1.1P in COS10001. (#{index})",
        link: @notification.link
      )

      tag_for(burst)
    end

    # Three different ids, one tag. If the id were part of it there would be
    # three, so this is the assertion that pins the id out of the tag.
    assert_equal 1, tags.uniq.length, tags.inspect
  end

  # The one that decides between keying on the event and keying on
  # notification_type. notification_type is only the preference category, so
  # task_due_date_changed, task_status_changed, new_task_available and
  # task_due_soon are all `task`. Keyed on that, a status change would silently
  # take the place of a deadline alert about the same task, which is the failure
  # this ticket exists to avoid rather than one to introduce.
  def test_different_events_in_the_same_category_do_not_share_a_tag
    deadline = Notification.create!(
      user: @user,
      notification_type: 'task',
      event: 'task_due_date_changed',
      message: 'The due date for 1.1P in COS10001 has changed.',
      link: @notification.link
    )
    due_soon = Notification.create!(
      user: @user,
      notification_type: 'task',
      event: 'task_due_soon',
      message: '1.1P in COS10001 is due soon.',
      link: @notification.link
    )

    assert_equal deadline.notification_type, due_soon.notification_type
    assert_not_equal tag_for(deadline), tag_for(due_soon)
  end

  # link is nullable on the api, and there is nothing else to be about. Sharing
  # one empty tag between every notification that happens to have no link would
  # hide all but the newest of them.
  def test_a_notification_with_no_link_collapses_with_nothing
    first = Notification.create!(
      user: @user, notification_type: 'general', event: 'system_announcement', message: 'One'
    )
    second = Notification.create!(
      user: @user, notification_type: 'general', event: 'system_announcement', message: 'Two'
    )

    assert_not_equal tag_for(first), tag_for(second)
    assert tag_for(first).present?
  end

  # Silent replacement is the point. renotify: true puts the sound and the
  # vibration back on every message in the burst the tag exists to quieten.
  def test_a_replacement_does_not_buzz_again
    body = JSON.parse(PushNotificationService.payload_for(@notification))['notification']

    assert_equal false, body['renotify']
  end

  # MN-D01 and MN-D05 own the wording. This ticket only adds the tag, so a
  # change to either of those here is somebody else's work being overwritten.
  def test_the_title_and_body_are_left_alone
    body = JSON.parse(PushNotificationService.payload_for(@notification))['notification']

    assert_equal 'Andrew Cain commented on 1.1P in COS10001.', body['body']
    assert_equal Doubtfire::Application.config.institution[:product_name], body['title']
  end

  def test_a_long_message_is_trimmed_rather_than_rejected_by_the_push_service
    @notification.update!(message: 'a' * 500)

    body = JSON.parse(PushNotificationService.payload_for(@notification))['notification']['body']

    assert_operator body.length, :<=, PushNotificationService::MAX_BODY_LENGTH
  end

  # The shared fan-out queues an ID-only job, and the worker calls this service
  # with no per-event push wiring.
  def test_raising_a_notification_through_the_hub_queues_and_delivers_a_push
    create_subscription
    request = stub_request(:post, ENDPOINT).to_return(status: 201)
    notification = NotificationService.notify(
      user: @user,
      type: 'feedback',
      event: 'task_comment_created',
      message: 'Raised through the hub.',
      link: '/projects/2/dashboard/1.1P'
    )

    assert_equal [notification.id], PushNotificationDeliveryJob.jobs.last['args']
    assert_not_requested request

    with_keys { PushNotificationDeliveryJob.new.perform(notification.id) }
    assert_requested request
  end

  # Rows written before PushSubscription validated the endpoint were never
  # checked, so the service refuses at send time as well. This is the line that
  # actually stops a stored bad endpoint being used, so it is tested by writing
  # a row that skips validation, the way an old row would look.
  def test_a_stored_endpoint_that_is_not_a_push_service_is_never_requested
    subscription = FactoryBot.build(:push_subscription, user: @user, endpoint: 'https://169.254.169.254/latest/meta-data/')
    subscription.save!(validate: false)

    # No WebMock stub is registered for that host, so an outbound request would
    # raise rather than pass silently.
    with_keys { PushNotificationService.deliver(@notification) }

    assert_not_requested :post, 'https://169.254.169.254/latest/meta-data/'
    assert subscription.reload.persisted?, 'a refused endpoint should be left alone, not treated as dead'
  end

  def test_a_refused_endpoint_does_not_stop_the_other_browsers
    FactoryBot
      .build(:push_subscription, user: @user, endpoint: 'https://10.0.0.5/internal')
      .save!(validate: false)
    create_subscription
    good = stub_request(:post, ENDPOINT).to_return(status: 201)

    with_keys { PushNotificationService.deliver(@notification) }

    assert_requested good
  end

  # Timeouts are Net::HTTP settings rather than anything visible on the wire, so
  # WebMock cannot see them. This one test stubs the gem instead of the HTTP
  # call, which is the opposite of what the rest of this file does on purpose.
  #
  # It is worth the exception because web-push sets no timeouts of its own, and
  # because the gem only applies read_timeout when open_timeout is also present
  # (lib/web_push/request.rb line 15), so passing one without the other silently
  # does nothing.
  def test_delivery_limits_and_timeouts_are_passed_to_the_gem
    create_subscription
    captured = nil

    WebPush.stub(:payload_send, ->(**args) { captured = args }) do
      with_keys { PushNotificationService.deliver(@notification) }
    end

    assert_equal PushNotificationService::OPEN_TIMEOUT, captured[:open_timeout]
    assert_equal PushNotificationService::READ_TIMEOUT, captured[:read_timeout]
    assert_equal PushNotificationService::SSL_TIMEOUT, captured[:ssl_timeout]
    assert_equal PushNotificationService::MESSAGE_TTL, captured[:ttl]
    assert_equal PushNotificationService::MESSAGE_URGENCY, captured[:urgency]
  end
end
