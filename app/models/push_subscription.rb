# One browser registered to receive web push notifications.
#
# The endpoint is the URL the push service gave that browser. It identifies the
# browser, not the person, so it is unique across the whole table: if the same
# browser signs in as a different user the registration moves across instead of
# being duplicated. PushSubscriptionsApi does that move.
#
# The endpoint arrives from the client and the api later makes an outbound POST
# to it, so it is not free text. It has to be an https URL belonging to a push
# service we recognise, or a signed in user could point the api at an internal
# host and use it to make requests on their behalf. See PUSH_SERVICE_HOSTS.
class PushSubscription < ApplicationRecord
  # Exact hosts. One per push service.
  #
  #   fcm.googleapis.com                  Chrome, Opera, Brave
  #   android.googleapis.com              older Chrome on Android
  #   updates.push.services.mozilla.com   Firefox
  #
  # A verified Edge 151 subscription on macOS used WNS even though Edge is
  # Chromium. Endpoint selection can vary by platform or release, so these
  # labels are observations rather than a browser-detection contract.
  PUSH_SERVICE_HOSTS = %w[
    fcm.googleapis.com
    android.googleapis.com
    updates.push.services.mozilla.com
  ].freeze

  # Suffixes, for the services that shard across per-region subdomains. Matched
  # with a leading dot so "evil-notify.windows.com" cannot pass as a subdomain
  # of "notify.windows.com".
  #
  #   *.notify.windows.com               WNS, current Edge observed
  #   *.push.services.microsoft.com      WNS, current
  #   *.push.apple.com                    Safari, iOS 16.4+
  #
  # Not legacy. Edge 151 on macOS subscribed through
  # wns2-bl2p.notify.windows.com when this was checked on 27 Aug 2026. Do not
  # infer a browser only from an endpoint host; the testing guide records the
  # scoped observation and the allow-list accepts the supported services.
  PUSH_SERVICE_HOST_SUFFIXES = %w[
    .notify.windows.com
    .push.services.microsoft.com
    .push.apple.com
  ].freeze

  belongs_to :user

  validates :endpoint, presence: true, uniqueness: true, length: { maximum: 500 }
  validates :p256dh, presence: true, length: { maximum: 255 }
  validates :auth, presence: true, length: { maximum: 255 }

  # A p256dh is a 65-byte uncompressed prime256v1 public key and an auth is a
  # 16-byte secret, both base64url from the browser's PushSubscription. The
  # length validations above only bound the string; a key of the wrong charset
  # or decoded length still passes them and then fails deep inside web-push's
  # encryption with an error that is neither ExpiredSubscription nor
  # InvalidSubscription. Nothing retires such a row, so every push to that user
  # fails the fan-out and Sidekiq retries, re-hitting the healthy devices too.
  # Check the decoded shape on the way in.
  P256DH_BYTES = 65
  AUTH_BYTES = 16

  validate :endpoint_is_a_known_push_service
  validate :encryption_keys_are_usable

  # Accept base64url material of the expected size, and validate the actual
  # curve point for a public key. A correctly sized byte string alone can
  # still fail encryption and prevent delivery to the user's other devices.
  #
  # Also called at delivery time, because rows written before this validation
  # existed were never checked. Keep it a class method for that reason, the same
  # as push_service_endpoint?.
  def self.valid_web_push_key?(value, expected_bytes)
    return false unless value.is_a?(String) && value.present?

    normalized = value.tr('-_', '+/')
    normalized = normalized.ljust((normalized.length + 3) & ~3, '=')
    decoded = Base64.strict_decode64(normalized)
    return false unless decoded.bytesize == expected_bytes
    return true unless expected_bytes == P256DH_BYTES
    return false unless decoded.getbyte(0) == 4

    group = OpenSSL::PKey::EC::Group.new('prime256v1')
    point = OpenSSL::PKey::EC::Point.new(group, OpenSSL::BN.new(decoded, 2))
    point.on_curve? && !point.infinity?
  rescue ArgumentError, OpenSSL::OpenSSLError
    false
  end

  # True when this endpoint is one we are willing to send to.
  #
  # Also called at delivery time, because rows written before this validation
  # existed were never checked. Keep it a class method for that reason.
  def self.push_service_endpoint?(endpoint)
    return false if endpoint.blank?

    uri = URI.parse(endpoint.to_s)

    # https only. http would send the encrypted payload in the clear and is not
    # something any real push service offers.
    return false unless uri.is_a?(URI::HTTPS)

    # user:password@host is a redirect trick, and a non standard port is a sign
    # somebody is aiming this somewhere it should not go. No push service uses
    # either.
    return false if uri.userinfo.present?
    return false unless uri.port == 443

    host = uri.host.to_s.downcase
    return false if host.blank?

    PUSH_SERVICE_HOSTS.include?(host) ||
      PUSH_SERVICE_HOST_SUFFIXES.any? { |suffix| host.end_with?(suffix) }
  rescue URI::InvalidURIError
    false
  end

  private

  def endpoint_is_a_known_push_service
    return if endpoint.blank? # presence validation already covers this

    return if self.class.push_service_endpoint?(endpoint)

    errors.add(:endpoint, 'must be an https URL belonging to a recognised push service')
  end

  def encryption_keys_are_usable
    # Blank is left to the presence validations so a missing key is not reported
    # twice.
    if p256dh.present? && !self.class.valid_web_push_key?(p256dh, P256DH_BYTES)
      errors.add(:p256dh, 'must be a base64url prime256v1 public key')
    end

    if auth.present? && !self.class.valid_web_push_key?(auth, AUTH_BYTES)
      errors.add(:auth, 'must be a 16-byte base64url secret')
    end
  end
end
