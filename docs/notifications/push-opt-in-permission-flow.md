# Push opt-in and permission flow

MN-D02. This document records the user-visible flow for enabling and disabling
Web Push on one device, the browser and server state behind it, and the recovery
path for each known failure.

This is a documentation-only ticket. It does not change permission, subscription,
delivery, or sign-out behaviour.

Push is device-specific. Turning it on stores this browser's subscription for
the signed-in user; it does not opt every browser or phone into push. Existing
notification category preferences still apply. For example, turning task
notifications off prevents task notifications on every channel, even when this
device remains subscribed to push.

For server configuration, payload shape, and delivery diagnostics, read
[`push-setup.md`](./push-setup.md). For secure-context rules, service-worker
cleanup, and phone tunnel setup, read
[`testing-push-locally.md`](./testing-push-locally.md).

## Happy path

The browser permission prompt must follow a user action. OnTrack therefore asks
for permission only after the user clicks the push setting; it never prompts on
sign-in or page load.

```text
Sign in
  -> open Profile
  -> wait for the service worker to start
  -> click "Turn on push notifications on this device"
  -> grant the browser's notification permission
  -> browser creates a PushSubscription using the server's VAPID public key
  -> web app POSTs endpoint, p256dh, and auth to /api/push_subscriptions
  -> api stores or updates the subscription for the signed-in user
  -> another user action raises a notification event
  -> api sends the push through the stored endpoint
  -> service worker displays the notification
```

In more detail:

1. The user signs in and opens **Profile**. The push control is part of the
   edit-profile form, below the notification category settings.
2. The Angular service worker registers about six seconds after application
   bootstrap. Until it is ready, the button is disabled and the page says:
   **Still starting up. This becomes available a few seconds after the page
   loads.**
3. `PushNotificationService.blocker()` checks that the browser exposes the
   Notifications and Push APIs, permission has not already been denied, VAPID
   is configured, and `SwPush` is enabled.
4. The user clicks **Turn on push notifications on this device**. The button is
   disabled while the request is running so a second click cannot create a
   competing request.
5. `SwPush.requestSubscription` asks the browser for permission and supplies
   the VAPID public key published by the api.
6. After permission is granted, the browser returns a subscription. The web app
   posts its `endpoint`, `p256dh`, and `auth` values to the authenticated
   `POST /api/push_subscriptions` endpoint.
7. The api validates the endpoint as a recognised HTTPS push service and stores
   it for the current user. Posting the same endpoint again updates its keys
   rather than creating a duplicate. If the endpoint previously belonged to
   another account on the same browser, ownership moves to the current user.
8. The page shows **This device will receive push notifications**, the button
   changes to **Turn off push notifications on this device**, and a toast says
   **Push notifications turned on**.
9. When an enabled notification event is raised,
   `NotificationService.notify` creates the in-app notification and calls the
   push delivery service. The service sends the Angular notification payload to
   every stored subscription for the recipient. `ngsw-worker.js` displays it.

Permission and subscription are different state. Browser permission allows the
site to show notifications. The `PushSubscription` gives the api a destination
and encryption keys. A user needs both, plus an active service worker and an
enabled notification category, before an event can appear as a push.

## What the user sees

| State                                | Push control                                     | User-visible result                                                                                                                                      | Recovery                                                                                                                |
| ------------------------------------ | ------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Service worker is starting           | Disabled                                         | **Still starting up. This becomes available a few seconds after the page loads.**                                                                        | Wait at least six seconds. If it persists, follow the service-worker checks below.                                      |
| Ready, permission is `default`       | Enabled                                          | **Turn on push notifications on this device**                                                                                                            | Click the button and choose **Allow** in the browser prompt.                                                            |
| Subscribing                          | Disabled                                         | The existing button remains visible while the request runs.                                                                                              | Wait for the success or error toast; do not reload during the prompt.                                                   |
| Subscribed                           | Enabled                                          | **Turn off push notifications on this device**, plus **This device will receive push notifications.**                                                    | No action is needed. A real event is still required to prove delivery.                                                  |
| Permission denied                    | Disabled                                         | **You have blocked notifications for this site**, followed by browser-specific steps for Chrome, Edge, or Firefox, or generic steps for another browser. | Allow notifications in site settings and reload. A site cannot override a denial or prompt again by itself.             |
| Push API unsupported                 | Disabled                                         | **This browser does not support push notifications.**                                                                                                    | Use a browser and device that expose Web Push in a secure context, and check that platform's installation requirements. |
| VAPID not configured                 | Disabled                                         | **Push notifications are not set up on this server.**                                                                                                    | An operator must configure the api. The user cannot correct this in the browser.                                        |
| Request fails after a denial         | Disabled on the next state check                 | Toast: **Notifications are blocked in your browser**.                                                                                                    | Change the site's notification permission to Allow, then reload.                                                        |
| Other subscribe or unsubscribe error | Depends on the browser subscription that remains | Toast: **Could not change push notifications**.                                                                                                          | Check the api response and logs, then retry. Do not treat the toast as evidence that local and server state match.      |

The browser-specific denial instructions come from
`PERMISSION_DENIED_INSTRUCTIONS` in the web push service. Opera and unrecognised
browsers deliberately use the generic instructions rather than Chrome's steps.

## Failure and recovery paths

### Permission was denied

`Notification.permission === 'denied'` is a hard blocker. OnTrack disables the
button because browsers do not let a site reverse that decision or show the
permission prompt again. The page explains how to reopen the site's permission
settings for Chrome, Edge, and Firefox. After changing the permission, reload so
the blocker and the local subscription are read again.

If the user denies the first prompt, `requestSubscription` rejects. The immediate
feedback is the **Notifications are blocked in your browser** toast; after the
state refresh or reload, the disabled control and recovery steps explain what to
do next.

### The browser or context is unsupported

OnTrack reports **This browser does not support push notifications** when either
`Notification` or `PushManager` is absent. This can mean the browser genuinely
lacks Web Push, but it can also mean the page is outside a secure context.

`http://localhost` is treated as trustworthy for local development. A phone
opened at a laptop's plain HTTP LAN address is not. Use HTTPS for a real device
and check:

```js
window.isSecureContext && "serviceWorker" in navigator;
```

The result must be `true`. The phone and tunnel procedure is in
[`testing-push-locally.md`](./testing-push-locally.md).

### The service worker is missing or stuck

`SwPush.isEnabled` is false during the normal six-second registration delay and
when the current build did not generate or register `ngsw-worker.js`. Both cases
show the same temporary starting-up message.

If the button stays disabled:

1. Request `/ngsw-worker.js` and confirm it returns `200`, not `404`.
2. Confirm the browser shows an activated service worker for the current origin.
3. Clear stale registrations and caches using
   `doubtfire-web/docs/service-worker.md` or the browser-specific steps in
   [`testing-push-locally.md`](./testing-push-locally.md).
4. Reload and wait for registration before reopening the push setting.

### The subscription expired or was invalidated

When a push service answers `404` or `410`, the api treats the registration as
dead and deletes its `push_subscriptions` row. Temporary failures stay inside
the asynchronous delivery path: they are raised to Sidekiq for retry and never
propagate to the original request, in-app record, or email hand-off.

There is currently no message back to the open browser when this cleanup
happens. Its local `SwPush.subscription` can therefore still make Profile say
**This device will receive push notifications** even though the api no longer
has a destination. The symptom is a subscribed-looking device that receives no
push and has no row on the api.

To recover today, click **Turn off push notifications on this device** and then
turn it on again. The web app still removes the local subscription when the api
delete returns `404`, so a fresh opt-in can create and store a new endpoint.
Automatic re-registration when a browser rotates its subscription belongs to
MN-C05; this flow does not claim it already happens.

### The operating system muted the browser

Browser permission can be `granted` while the operating system blocks the
browser's notifications, Focus or Do Not Disturb suppresses them, or the alert
style shows no banner. The web app cannot see those operating-system settings.
It continues to show **This device will receive push notifications**, and the
api can successfully send, while nothing appears on screen.

Use a local notification to separate an operating-system problem from an
OnTrack delivery problem:

```js
const registration = await navigator.serviceWorker.ready;
await registration.showNotification("OnTrack", {
  body: "Local notification test; no api or push service involved",
});
```

If this does not appear, allow notifications for the browser in the operating
system, choose a visible alert style, and turn off Focus or Do Not Disturb. If it
does appear, continue with the subscription, recipient, VAPID, and api-log checks
in [`push-setup.md`](./push-setup.md).

### A delivery service or api call failed

Temporary push errors are logged and the server keeps the subscription. One
failing browser never blocks delivery to the recipient's other devices and
never blocks the in-app notification or email.

A failed opt-in API request produces **Could not change push notifications**.
Because the browser may already have created its local subscription before the
POST fails, verify both sides rather than relying on the toast:

```js
await navigator.serviceWorker.ready.then((registration) =>
  registration.pushManager.getSubscription(),
);
```

```sh
docker exec doubtfire-api bundle exec rails runner \
  'puts PushSubscription.all.map { |s| "#{s.user.username} #{s.endpoint[0, 60]}" }'
```

If the local subscription exists but the api row does not, turn push off and on
after correcting the api error.

## Revoking push on this device

Clicking **Turn off push notifications on this device** performs two operations
in this order:

1. `DELETE /api/push_subscriptions?endpoint=...` removes the signed-in user's
   server row while the auth token and endpoint still exist.
2. `SwPush.unsubscribe()` removes the browser subscription.

Server deletion goes first because local unsubscribe discards the endpoint the
api needs to find the row. If the delete fails, the web app still unsubscribes
locally. The leftover server row is harmless and is removed when a later send
receives `404` or `410`. On success, the toast says **Push notifications turned
off** and the control returns to its opt-in state.

Revoking the site's permission directly in browser settings is different from
using the OnTrack button. The page can detect that permission is now denied, but
the current code does not proactively delete the api row in response to a
permission change. Browser cleanup varies; any dead row is removed after the
push service reports it as expired or invalid. Use the OnTrack control when
possible so both sides are cleaned up deliberately.

## Sign-out ordering

Sign-out also removes push because a browser subscription survives an ordinary
web session. Leaving it behind on a shared device could send the previous
user's notifications after another person signs in.

`AuthenticationService.signOut` therefore:

1. calls `PushNotificationService.unsubscribeQuietly()` while the current
   user's auth token still exists;
2. deletes the api row before unsubscribing in the browser;
3. continues deleting the server session and local auth token whether push
   cleanup succeeds or fails; and
4. completes sign-out even when the service worker is disabled or the browser
   refuses to unsubscribe.

The quiet variant is deliberate: push cleanup protects a shared device, but an
outage must never trap someone in a signed-in session. When there is no active
service worker, sign-out cannot read a local endpoint and returns immediately;
any server row it could not address is left for delivery-time cleanup.

## Source map

| Responsibility                                                    | Source                                                                                      |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| Push control, status text, busy state, and toasts                 | `doubtfire-web/src/app/common/edit-profile-form/edit-profile-form.component.ts` and `.html` |
| Blocker order, browser guidance, subscribe, and unsubscribe       | `doubtfire-web/src/app/api/services/push-notification.service.ts`                           |
| Service-worker registration delay                                 | `doubtfire-web/src/app/doubtfire-angular.module.ts`                                         |
| Sign-out cleanup ordering                                         | `doubtfire-web/src/app/api/services/authentication.service.ts`                              |
| Authenticated store, update, ownership move, and delete endpoints | `doubtfire-api/app/api/push_subscriptions_api.rb`                                           |
| Endpoint validation and uniqueness                                | `doubtfire-api/app/models/push_subscription.rb`                                             |
| Push fan-out, payload, expired-row cleanup, and error isolation   | `doubtfire-api/app/services/push_notification_service.rb`                                   |

## Verification boundary

The service and API tests cover the state decisions and request ordering, but
they cannot prove that a browser or operating system displayed a notification.
A complete manual verification must record the browser and OS versions, grant
permission through the Profile control, confirm the api row, trigger a real
event for the subscribed user, observe the notification, and test its click
destination. Use the local testing guide for that end-to-end procedure.
