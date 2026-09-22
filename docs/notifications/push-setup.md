# Web push setup

How the push channel works, how to turn it on, and how to check it is working.

## What push needs

Three things, and push is a no-op until all three are true:

1. **VAPID keys on the api.** Without them `PushNotificationService.configured?`
   is false and `deliver` returns immediately. The app behaves exactly as it did
   before push existed.
2. **A row in `push_subscriptions`.** A browser has to register itself first.
   MN-F01 added the table and the API.
3. **A service worker in the browser.** MN-F03 turns it on for development.
   Without it, the browser has nothing to receive a push with. Setup,
   caching side effects and how to clear a stuck worker are in the web repo:
   `doubtfire-web/docs/service-worker.md`.

Miss any one and nothing arrives, with no error anywhere. Check them in order.

## The keys

VAPID is how a push service knows the push came from us and not from anyone else
who happens to know a browser's endpoint URL. It is one key pair for the whole
server, not one per user.

Generate a pair:

    docker exec doubtfire-api bundle exec ruby -e \
      "require 'web_push'; k = WebPush.generate_key; puts k.public_key; puts k.private_key"

Then set three environment variables on the api:

| Variable | What it is |
|---|---|
| `DOUBTFIRE_VAPID_PUBLIC_KEY` | Public half. The browser needs this to subscribe. |
| `DOUBTFIRE_VAPID_PRIVATE_KEY` | **Secret.** Signs every push. Never commit a real one. |
| `DOUBTFIRE_VAPID_SUBJECT` | A `mailto:` or URL the push service can contact. Optional; falls back to the institution host. |

`development/docker-compose.yml` in the deploy repo already carries a throwaway
pair so the local stack works out of the box, on the same footing as
`DF_SECRET_KEY_BASE`. That pair is development only. **A production deployment
sets its own through real secrets, and if the private key ever leaks, generate a
new pair — every existing subscription becomes useless and users have to
re-subscribe.**

Changing the keys does not migrate anything. The `push_subscriptions` rows stay,
but pushes signed with the new key are rejected for browsers that subscribed
under the old one. The delivery service deliberately retains generic failures,
including 403 responses, because they can also be transient configuration
errors. When rotating a VAPID pair, explicitly delete all existing
`push_subscriptions` rows and tell users to enable push again.

## How a notification becomes a push

`NotificationService.notify` queues `PushNotificationDeliveryJob` with only the
notification id. A Sidekiq worker reloads the notification and calls
`PushNotificationService.deliver`, so **every event that queues an email also
queues a push, with no per-event work**. Provider network I/O never blocks the
request or runs under the notification hand-off lock. Push jobs use the
dedicated `notifications` queue; every environment that enables Web Push must
run a worker for that queue.

`deliver` loops over `notification.user.push_subscriptions` and sends this
payload to each:

```json
{
  "notification": {
    "title": "OnTrack",
    "body": "Andrew Cain commented on 1.1P in COS10001.",
    "data": { "notification_id": 12, "link": "/projects/2/dashboard/1.1P" }
  }
}
```

The top level `notification` key matters. Angular's own `ngsw-worker.js` looks
for exactly that and displays the notification itself. **Change the shape and
somebody has to write a service worker by hand.**

`data.link` is what MN-C03 reads to decide where to send the user on click.
Delivery uses normal urgency and a one-hour TTL so a short disconnect can
recover without a push service surfacing workflow alerts days or weeks late.

## Failure handling

- **404 or 410** means the browser threw the registration away. The row is
  deleted, because nothing will ever reach it again.
- **Anything else** (429 rate limit, the push service being down, a rejected
  payload) is logged and retained. Delivery continues to the user's remaining
  browsers, then the aggregate failure is raised so Sidekiq can retry. The
  subscription is kept because deleting on a temporary outage would silently
  unsubscribe people the first time a push service had a bad day.
- The delivery job is configured for three Sidekiq retries. A missing
  notification row is also retryable because a fast worker may run before an
  enclosing producer transaction commits.
- Nothing propagates to the request caller. A push failure must never block the
  in-app notification or the email hand-off.

## Checking it works

**Are the keys loaded?**

    docker exec doubtfire-api bundle exec rails runner \
      'puts PushNotificationService.configured?'

`false` means the api container was started before the variables were added.
`restart` does not pick up new environment variables. Recreate it:

    docker compose -f docker-compose.yml -f docker-compose.local-paths.yml up -d doubtfire-api

**Is a browser registered?**

    docker exec doubtfire-api bundle exec rails runner \
      'puts PushSubscription.all.map { |s| "#{s.user.username} #{s.endpoint[0, 60]}" }'

Empty means nothing has subscribed yet. That is the usual reason a push does not
arrive, and it looks identical to push being broken.

**Subscribe this browser by hand for diagnostics.** The normal path is the
in-app opt-in control. To isolate that UI from the API and service worker, paste
this into the dev tools console on a page where you are signed in.

```js
const VAPID = '<the public key>'
const b64 = s => Uint8Array.from(atob(s.replace(/-/g,'+').replace(/_/g,'/')), c => c.charCodeAt(0))

const reg = await navigator.serviceWorker.ready
const sub = await reg.pushManager.subscribe({
  userVisibleOnly: true,
  applicationServerKey: b64(VAPID)
})
const j = sub.toJSON()

await fetch('/api/push_subscriptions', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Username': localStorage.getItem('username'),
    'Auth-Token': localStorage.getItem('authToken')
  },
  body: JSON.stringify({ endpoint: j.endpoint, p256dh: j.keys.p256dh, auth: j.keys.auth })
})
```

Then raise a notification (post a task comment) and a desktop notification
should appear.

**Nothing appeared?** Check in this order, because each step is invisible when it
fails:

1. Browser notification permission. `Notification.permission` must be `granted`.
   macOS also has to allow notifications from the browser, in System Settings.
2. `PushNotificationService.configured?` is true.
3. A `push_subscriptions` row exists for the user the notification went to. It is
   easy to subscribe as one account and then trigger a notification for another.
4. The Sidekiq worker consumes the `notifications` queue. The normal development
   stack starts it with `-q mailers -q notifications`; it deliberately does not
   consume the unrelated `default` queue.
5. `docker logs doubtfire-sidekiq | grep -i "push"`. Delivery failures happen in
   the worker, so this is the process that reports them.

## Why the gem is pinned

`Gemfile` pins `web-push` to exactly `3.0.1`. This release still depends on
`jwt ~> 2.0`, so it remains compatible with the authentication dependencies in
this release, while replacing the separate `hkdf` gem with `OpenSSL::KDF`.
`web-push` 3.0.2 is the release that moves to JWT 3; upgrading beyond 3.0.1
therefore needs authentication and OAuth regression testing.
