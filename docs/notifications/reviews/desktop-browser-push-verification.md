# MN-Q01 – Desktop browser push verification

## Result

**Blocked — not passed.** No successful push delivery or notification
click-through was observed in Chrome, Edge, or Firefox during this verification
attempt on 23 August 2026.

This report records the evidence that was collected and the precise work still
needed. It must not be treated as browser sign-off. The blocker was access to
controllable sessions in the required browsers, not a demonstrated OnTrack code
defect.

## Environment

- OnTrack web: `feature/notifications` at `60b9ab7af`
- OnTrack api: `feature/notifications` at `564ff793f`
- Host: macOS 26.6.2 (25G83), Apple silicon
- Google Chrome: 151.0.7922.139
- Microsoft Edge: 151.0.4129.101
- Mozilla Firefox: 147.0.4
- Test origin: `http://localhost:4200`

The browser versions were read from the installed application bundles. Each
required browser was installed, but an installed browser is not evidence that
the push flow ran successfully in it.

## Preflight evidence

The local notification stack was started from the notification feature branches
and checked before attempting browser verification:

| Check                                  | Observed result |
| -------------------------------------- | --------------- |
| Web app at `http://localhost:4200/`    | HTTP 200        |
| Api endpoint                           | HTTP 200        |
| `http://localhost:4200/ngsw-worker.js` | HTTP 200        |
| `PushNotificationService.configured?`  | `true`          |
| `push_subscriptions` table present     | `true`          |
| Existing push subscription count       | `0`             |

These results show that the app, api, service-worker asset, VAPID configuration,
and database table were available. They do not prove that any browser subscribed
or received a push. The zero subscription count confirms that no subscription
was created during this run.

## Browser results

| Browser               | Permission and subscription                                                                                                    | Real event delivery | Click-through | Screenshot | Result                   |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------ | ------------------- | ------------- | ---------- | ------------------------ |
| Chrome 151.0.7922.139 | Not run. Browser control reported that Chrome was unavailable.                                                                 | Not observed        | Not tested    | None       | **Blocked / not passed** |
| Edge 151.0.4129.101   | Not run. Browser control reported that Edge was unavailable.                                                                   | Not observed        | Not tested    | None       | **Blocked / not passed** |
| Firefox 147.0.4       | Not run. Firefox was not supported by the available browser-control session and no controllable Firefox session was available. | Not observed        | Not tested    | None       | **Blocked / not passed** |

The in-app browser was used only as a diagnostic. Its notification permission
was already `denied`; the Profile push control was disabled and no subscription
was created. It is not Chrome, Edge, or Firefox, so that result does not satisfy
this ticket for any of the three required browsers.

There are deliberately no notification screenshots attached to this report:
no required browser produced a notification. Likewise, no real event delivery
or notification click-through is claimed.

## Rerun procedure

Run the following sequence separately in Chrome, Edge, and Firefox. Do not carry
a subscription, service-worker cache, or permission result from one browser into
another browser's evidence.

1. Check out the current `feature/notifications` branches for both web and api,
   start the local stack, and record the web and api commit hashes.
2. Confirm that the web app, api, and `/ngsw-worker.js` each return HTTP 200.
3. In the api container, confirm that `PushNotificationService.configured?` is
   `true` and that the `push_subscriptions` table exists.
4. Reset notification permission for `http://localhost:4200` to **Ask**, clear
   the origin's service worker and site data, then reload. Also confirm that
   macOS allows the browser application to show notifications and that Focus is
   off.
5. Sign in as the intended recipient, wait for the service worker to register,
   open Profile, and use the push opt-in control. Grant the native notification
   permission when prompted.
6. Record `Notification.permission`, service-worker registration state, and the
   push-subscription rows before and after opt-in. Verify that exactly the
   expected user's subscription was added or updated.
7. From a second authorised account, trigger a real notification event such as
   posting a task comment for the subscribed recipient. Do not use a DevTools
   synthetic push because it does not test api delivery.
8. With the recipient tab unfocused, verify that the operating-system
   notification appears. Capture a screenshot showing the browser, operating
   system, timestamp, title, and privacy-safe body.
9. Click the notification and verify that OnTrack focuses or opens and navigates
   to the event's expected route. Record the actual route and capture evidence.
10. Check api logs for push delivery failures and confirm whether the
    subscription row remains present. Record any browser-console or api error
    verbatim in the result table.
11. Sign out or remove the test subscription before moving to the next browser,
    then repeat from step 4 in a fresh browser profile.

## Completion criteria for the follow-up run

MN-Q01 can be signed off only when all three browser rows contain:

- a granted permission and persisted subscription;
- a visible notification produced by a real OnTrack event;
- a successful click-through to the intended page; and
- dated screenshot evidence, with any private information redacted.

If a browser fails after preflight succeeds, create a separate bug containing
the browser version, reproduction steps, service-worker state, subscription
evidence, api log excerpt, expected result, and actual result. Until that run is
completed, this ticket remains blocked and must not be marked passed.
