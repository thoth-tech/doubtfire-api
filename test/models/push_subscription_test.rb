require 'test_helper'

# The endpoint arrives from the browser and PushNotificationService later makes
# an outbound POST to it, so anything that is not a real push service URL has to
# be refused on the way in.
class PushSubscriptionTest < ActiveSupport::TestCase
  setup do
    @user = FactoryBot.create(:user, :student)
  end

  def build_with(endpoint)
    FactoryBot.build(:push_subscription, user: @user, endpoint: endpoint)
  end

  # Every service we actually expect to see, so a future change to the list
  # cannot quietly drop a browser.
  ACCEPTED = [
    'https://fcm.googleapis.com/fcm/send/abc123',
    'https://android.googleapis.com/gcm/send/abc123',
    'https://updates.push.services.mozilla.com/wpush/v2/abc123',
    'https://web.push.apple.com/abc123',
    'https://webcourier.push.apple.com/abc123',
    'https://par02p.notify.windows.com/w/?token=abc123',
    'https://wns2-by3p.push.services.microsoft.com/w/?token=abc123'
  ].freeze

  ACCEPTED.each_with_index do |endpoint, index|
    define_method("test_accepts_known_push_service_#{index}") do
      subscription = build_with(endpoint)

      assert subscription.valid?, "#{endpoint} should be accepted but was rejected with #{subscription.errors.full_messages}"
    end
  end

  # The SSRF cases. Each of these is a host an attacker would want the api to
  # make a request to on their behalf.
  REJECTED = {
    'plain http' => 'http://fcm.googleapis.com/fcm/send/abc',
    'localhost' => 'https://localhost/fcm/send/abc',
    'loopback ip' => 'https://127.0.0.1/fcm/send/abc',
    'link local metadata' => 'https://169.254.169.254/latest/meta-data/',
    'private range' => 'https://10.0.0.5/internal',
    'the api container itself' => 'https://doubtfire-api:3000/api/users',
    'an arbitrary host' => 'https://example.com/push',
    'userinfo redirect trick' => 'https://fcm.googleapis.com@evil.example.com/push',
    'non standard port' => 'https://fcm.googleapis.com:8080/fcm/send/abc',
    'suffix lookalike' => 'https://evil-notify.windows.com/w/?token=abc',
    'apple suffix without boundary' => 'https://evilpush.apple.com/abc',
    'apple suffix followed by another domain' => 'https://web.push.apple.com.evil.example/abc',
    'bare apple parent domain' => 'https://push.apple.com/abc',
    'host substring lookalike' => 'https://fcm.googleapis.com.evil.example.com/push',
    'not a url at all' => 'not a url',
    'file scheme' => 'file:///etc/passwd'
  }.freeze

  REJECTED.each do |name, endpoint|
    define_method("test_rejects_#{name.tr(' ', '_')}") do
      subscription = build_with(endpoint)

      assert_not subscription.valid?, "#{endpoint} (#{name}) should have been rejected"
      assert_includes subscription.errors[:endpoint].join, 'recognised push service'
    end
  end

  def test_the_factory_endpoint_is_accepted
    # Guards against the allowlist and the factory drifting apart, which would
    # break every other push test at once and look like an unrelated failure.
    assert FactoryBot.build(:push_subscription, user: @user).valid?
  end

  def test_push_service_endpoint_predicate_handles_blank_input
    assert_not PushSubscription.push_service_endpoint?(nil)
    assert_not PushSubscription.push_service_endpoint?('')
  end

  def test_an_endpoint_is_still_required
    subscription = build_with(nil)

    assert_not subscription.valid?
    assert_includes subscription.errors[:endpoint].join, "can't be blank"
  end
end
