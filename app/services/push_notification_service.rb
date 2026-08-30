# Web Push delivery channel.
#
# PushNotificationDeliveryJob calls this for every notification handed off by
# NotificationService. Two properties make that safe:
#
#   * without VAPID keys it is a no-op, so the app behaves exactly as it did
#     before push existed for anyone who has not configured them
#   * one browser failing never stops attempts to the others; transient failures
#     are raised only after fan-out so Sidekiq can retry the delivery job
#
# Because the shared fan-out queues the job, every event that queues an email
# also queues a push, with no per-event work.
#
# Key generation and setup: docs/notifications/push-setup.md.
class PushNotificationService
  class DeliveryError < StandardError; end

  # Push services reject a payload much over 4KB once encrypted. Nothing here
  # comes close, but the message is user-facing text assembled from names and
  # task titles, so it is trimmed rather than trusted.
  MAX_BODY_LENGTH = 400

  # Lock-screen copy is a separate channel from the richer in-app notification
  # and email. These v2 events contain free-form names or precise schedule data
  # in Notification#message, so use bounded, reviewed copy whenever the payload
  # is rendered. Keeping the decision here means direct delivery and any future
  # payload regeneration cannot accidentally bypass the privacy boundary.
  LOCK_SCREEN_BODY_OVERRIDES = {
    'tutorial_changed' => 'Your tutorial details changed.',
    'group_membership_changed' => 'Your group membership changed.',
    'task_submitted' => 'A task is ready for marking.',
    'portfolio_received' => 'Your portfolio submission was received.'
  }.freeze

  # MN-C03 BEGIN: safe click route constants
  SAFE_CLICK_FALLBACK = '/notifications'.freeze
  MAX_CLICK_LINK_LENGTH = 256
  FORBIDDEN_CLICK_LINK_TEXT = /[\u0000-\u001f\u007f\s\\?#%]/
  SAFE_PROJECT_ROOT_LINK = %r{\A/projects/[1-9]\d*/(?:dashboard|groups)\z}
  SAFE_PROJECT_TASK_LINK = %r{\A/projects/[1-9]\d*/dashboard/[A-Za-z0-9][A-Za-z0-9._-]{0,31}\z}x
  # MN-C03 END: safe click route constants
  # Seconds. web-push sets no timeouts of its own, so without these a push
  # service that accepts a connection and then never answers holds a Sidekiq
  # worker thread and reduces delivery capacity until the process kills it.
  #
  # Both are passed together on purpose. web-push 3.0.1 guards read_timeout on
  # open_timeout being present (lib/web_push/request.rb line 15), so passing
  # read_timeout alone silently does nothing.
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 5
  SSL_TIMEOUT = 5

  # Push services otherwise retain messages for the gem default of four weeks.
  # OnTrack notifications describe current workflow state, so delivering one
  # days or weeks later is misleading. One hour tolerates a short disconnect
  # without surfacing stale due-date or status alerts.
  MESSAGE_TTL = 1.hour.to_i
  MESSAGE_URGENCY = 'normal'.freeze

  def self.deliver(notification)
    return unless configured?

    subscriptions = notification.user.push_subscriptions.to_a
    return if subscriptions.empty?

    payload = payload_for(notification)

    failures = []
    subscriptions.each do |subscription|
      deliver_to(subscription, payload)
    rescue StandardError => e
      # Finish the fan-out before raising. This preserves delivery to healthy
      # browsers while ensuring a provider outage reaches Sidekiq's retry path.
      Rails.logger.error "Failed to push to subscription #{subscription.id}: #{e.class}"
      failures << e
    end

    return if failures.empty?

    raise DeliveryError,
          "Push delivery failed for #{failures.length} subscription(s)",
          cause: failures.first
  end

  # The shape Angular's own ngsw-worker.js understands. It looks for a top level
  # "notification" key and displays the notification itself, which is why none of
  # this needs a hand written service worker. Use any other shape and somebody
  # has to write one.
  #
  # data.link is what MN-C03 reads to decide where to send the user on click.
  #
  # tag and renotify are both in the service worker's own list of forwarded
  # option names (ngsw-worker.js, NOTIFICATION_OPTION_NAMES), so they reach
  # showNotification without any change on the web side.
  def self.payload_for(notification)
    click_link = safe_click_link(notification.link)

    {
      notification: {
        title: Doubtfire::Application.config.institution[:product_name],
        body: body_for(notification),
        tag: tag_for(notification),
        # False, so a replacement updates the banner without making a sound or
        # vibrating again.
        #
        # A burst is the case this exists for: a tutor working through one task
        # posts five comments in two minutes. The tag already collapses those
        # into one banner, and renotify: true would put the buzz back on every
        # one of them, which is most of what made the burst worth collapsing.
        # The user has already been interrupted once and the banner is already
        # on their screen saying the newest thing.
        #
        # The cost is that a genuinely new message inside an ongoing
        # conversation arrives silently while the old banner is still up. That
        # is the right way round: the person has been told, and the alternative
        # is being told five times.
        renotify: false,
        data: {
          notification_id: notification.id,
          link: click_link,
          onActionClick: {
            default: {
              operation: 'focusLastFocusedOrOpen',
              url: click_link
            }
          }
        }
      }
    }.to_json
  end

  def self.safe_click_link(link)
    return SAFE_CLICK_FALLBACK unless link.is_a?(String)
    return SAFE_CLICK_FALLBACK if link.empty? || link.length > MAX_CLICK_LINK_LENGTH
    return SAFE_CLICK_FALLBACK unless link == link.strip
    return SAFE_CLICK_FALLBACK if link.match?(FORBIDDEN_CLICK_LINK_TEXT)
    return link if link == SAFE_CLICK_FALLBACK || link.match?(SAFE_PROJECT_ROOT_LINK)
    return link if link.match?(SAFE_PROJECT_TASK_LINK)

    SAFE_CLICK_FALLBACK
  end

  def self.body_for(notification)
    LOCK_SCREEN_BODY_OVERRIDES
      .fetch(notification.event.to_s, notification.message.to_s)
      .truncate(MAX_BODY_LENGTH)
  end

  # Use the event and validated destination as the collapse key so repeated
  # pushes about the same event and task can replace one banner.
  #
  # notification_type is intentionally not used because several different
  # events share one category. For example, a task status change must not
  # silently replace a due-date warning about the same task.
  #
  # A missing or rejected destination receives a notification-specific tag.
  # This prevents unrelated downgraded notifications from replacing each other
  # and prevents the rejected raw route from being copied into the tag.
  def self.tag_for(notification)
    click_link = safe_click_link(notification.link)
    return "notification-#{notification.id}" unless click_link == notification.link

    "#{notification.event}:#{click_link}"
  end

  def self.deliver_to(subscription, payload)
    # Checked again here rather than trusted from the row. PushSubscription
    # validates this on write, but rows created before that validation existed
    # were never checked, and this is the line that actually makes the outbound
    # request. Refusing here is what stops a stored bad endpoint being used.
    unless PushSubscription.push_service_endpoint?(subscription.endpoint)
      Rails.logger.error "Refusing to push to subscription #{subscription.id}: endpoint is not a recognised push service"
      return
    end

    WebPush.payload_send(
      message: payload,
      endpoint: subscription.endpoint,
      p256dh: subscription.p256dh,
      auth: subscription.auth,
      vapid: vapid_details,
      ttl: MESSAGE_TTL,
      urgency: MESSAGE_URGENCY,
      open_timeout: OPEN_TIMEOUT,
      read_timeout: READ_TIMEOUT,
      ssl_timeout: SSL_TIMEOUT
    )
  rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription => e
    # 410 or 404. The browser has thrown this registration away, or it was never
    # valid. Nothing will ever reach it again, so drop the row rather than retry
    # it on every notification from here to the end of time.
    Rails.logger.info "Removing dead push subscription #{subscription.id}: #{e.class}"
    subscription.destroy
  end

  def self.vapid_details
    {
      subject: vapid_subject,
      public_key: ENV.fetch('DOUBTFIRE_VAPID_PUBLIC_KEY'),
      private_key: ENV.fetch('DOUBTFIRE_VAPID_PRIVATE_KEY')
    }
  end

  # Push services want a way to contact whoever is sending, as a mailto: or a
  # URL. They reject the request outright if it is missing.
  def self.vapid_subject
    ENV['DOUBTFIRE_VAPID_SUBJECT'].presence ||
      Doubtfire::Application.config.institution[:host].presence ||
      'mailto:noreply@doubtfire.local'
  end

  # True once VAPID keys are configured. Keeps the fan-out safe to call today.
  def self.configured?
    ENV['DOUBTFIRE_VAPID_PUBLIC_KEY'].present? && ENV['DOUBTFIRE_VAPID_PRIVATE_KEY'].present?
  end

  private_class_method :body_for, :safe_click_link, :deliver_to, :vapid_details, :vapid_subject
end
