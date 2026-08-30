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

  validate :endpoint_is_a_known_push_service

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
end
