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

  # DN-30: the keys must be usable web push material, not merely present and
  # under 255 characters. A malformed key passes the length validation and then
  # fails deep in web-push encryption, poisoning the fan-out for the user.
  def test_accepts_padded_keys_from_the_factory
    assert FactoryBot.build(:push_subscription, user: @user).valid?
  end

  def test_accepts_unpadded_keys
    # The same key pair as the factory, with the base64 padding stripped, which
    # is how a browser's PushSubscription usually presents it.
    subscription = FactoryBot.build(
      :push_subscription,
      user: @user,
      p256dh: 'BJy8RpjMkwOPDIIXSu-FTe7OosAwY9G86_evhrn0jJbPnoxXjBYpn7aPHEIaRh3GxCzFvwYXjKWvtu3FEMaBQMY',
      auth: 'CUkmaYqq8eINt1HTnFY65w'
    )

    assert subscription.valid?, subscription.errors.full_messages.join(', ')
  end

  def test_rejects_a_non_base64_p256dh
    subscription = FactoryBot.build(:push_subscription, user: @user, p256dh: 'not valid base64 !!')

    assert_not subscription.valid?
    assert_not_empty subscription.errors[:p256dh]
  end

  def test_rejects_a_wrong_length_p256dh
    # 'AAAA' is valid base64 but decodes to 3 bytes, not the 65 a prime256v1
    # public key needs.
    subscription = FactoryBot.build(:push_subscription, user: @user, p256dh: 'AAAA')

    assert_not subscription.valid?
    assert_not_empty subscription.errors[:p256dh]
  end

  def test_rejects_a_wrong_length_auth
    # Decodes to 3 bytes, not the 16 the auth secret must be.
    subscription = FactoryBot.build(:push_subscription, user: @user, auth: 'AAAA')

    assert_not subscription.valid?
    assert_not_empty subscription.errors[:auth]
  end

  def test_valid_web_push_key_predicate_rejects_blank_and_garbage
    assert_not PushSubscription.valid_web_push_key?(nil, PushSubscription::AUTH_BYTES)
    assert_not PushSubscription.valid_web_push_key?('', PushSubscription::AUTH_BYTES)
    assert_not PushSubscription.valid_web_push_key?('%%%not-base64%%%', PushSubscription::AUTH_BYTES)
  end

  def test_rejects_a_correct_length_key_that_is_not_a_curve_point
    invalid_point = Base64.urlsafe_encode64("\x04" + ("\x42" * 64))
    subscription = FactoryBot.build(:push_subscription, user: @user, p256dh: invalid_point)

    assert_not subscription.valid?
    assert_not_empty subscription.errors[:p256dh]
  end
end
