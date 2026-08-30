# MN-Q02 – Android phone push verification

## Result

**BLOCKED — NOT PASSED.** No physical Android phone was attached or otherwise
available for this verification on 23 August 2026 (Australia/Melbourne). The
required real-device delivery, lock-screen privacy, notification tap, and photo
evidence therefore do not exist.

A `Pixel_8_Pro` Android Virtual Device is installed on the test host. It was not
used as a substitute: this ticket explicitly requires a real Android phone and a
photo of its lock screen. The host also had no `cloudflared`, `ngrok`, or
`tailscale` client available to expose the local app through the HTTPS origin
required by a phone.

This report records the blocked attempt and the exact rerun needed to produce
valid evidence. It is not a sign-off of Android push support.

## Acceptance status

| Ticket check                                  | Result           | Evidence                                                                 |
| --------------------------------------------- | ---------------- | ------------------------------------------------------------------------ |
| Work started                                  | Met              | Verification branch and this test record exist.                          |
| Notification received on a real Android phone | **Not met**      | No physical Android phone was available.                                 |
| Nothing private visible                       | **Not verified** | No notification reached a real lock screen.                              |
| Click navigates correctly                     | **Not verified** | There was no real-device notification to tap.                            |
| Photo attached                                | **Not met**      | No real-device photo was produced.                                       |
| Lock screen photographed                      | **Not met**      | No physical lock screen was available.                                   |
| Wording matches MN-D01                        | **Not verified** | There is no observed title or body to compare with the approved wording. |

The administrative “started” check is the only completed item. The ticket must
remain open until every real-device check above is evidenced.

## Code and environment under review

| Item                         | Value                                                  |
| ---------------------------- | ------------------------------------------------------ |
| API base                     | `doubtfire-api` `feature/notifications` at `564ff793`  |
| Web base                     | `doubtfire-web` `feature/notifications` at `60b9ab7af` |
| Physical Android device      | **Unavailable**                                        |
| Android version              | Not recorded — no device                               |
| Chrome version on device     | Not recorded — no device                               |
| Installed virtual device     | `Pixel_8_Pro` (not acceptable as real-phone evidence)  |
| Public HTTPS tunnel          | **Unavailable**                                        |
| Photo or screenshot evidence | **None**                                               |

This branch adds only the test record. It does not change the push runtime.

## Local service preflight

The shared local QA setup was checked before the device step:

| Check                                                    | Observed result |
| -------------------------------------------------------- | --------------- |
| Web app at `http://localhost:4200/`                      | HTTP 200        |
| Service worker at `http://localhost:4200/ngsw-worker.js` | HTTP 200        |
| API at `http://localhost:3000/api/settings`              | HTTP 200        |
| `PushNotificationService.configured?`                    | `true`          |
| `push_subscriptions` table present                       | `true`          |
| Subscription rows                                        | `0`             |

These results show that the local services and development VAPID configuration
were present. They do not prove Android delivery. A phone cannot use the
laptop's `localhost`, and a plain HTTP LAN address is not a secure context for a
service worker or Push API. With no HTTPS tunnel and no physical device, no phone
could opt in and the empty subscription table was expected.

## Why execution stopped

The following blockers are independent of the application code:

1. No physical Android phone was available, so the defining acceptance condition
   could not be exercised.
2. No HTTPS tunnel client was available. Loading the app over a laptop's plain
   Wi-Fi address would not expose the service worker or Push API and would be an
   invalid test.
3. With no phone and no secure public origin, no Android subscription could be
   registered with the API.
4. Without a registered phone endpoint, there could be no server delivery,
   lock-screen observation, tap-through result, or real-device photo.

An emulator could help diagnose application behaviour later, but it cannot close
this ticket or supply the requested physical lock-screen evidence.

## Privacy scenarios that must be observed

The rerun must use synthetic course, user, and task data. For each observation,
compare the exact visible title and body with the approved MN-D01 wording rather
than inferring safety from the event name.

| Scenario                                                                   | Expected result                                                                                                                   |
| -------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| Phone locked and face up; Chrome or the installed PWA is in the background | A useful OnTrack notification is visible without unlocking the phone.                                                             |
| A bystander reads the collapsed notification                               | No comment text, feedback, mark, grade, authentication data, or other private detail is visible.                                  |
| Notification is expanded on the lock screen                                | Expansion reveals no additional private text.                                                                                     |
| Notification metadata is inspected                                         | The endpoint, authentication keys, tokens, and internal payload identifiers are not displayed.                                    |
| Test evidence is photographed                                              | Only synthetic data is shown; unrelated notifications, device identifiers, and personal account details are excluded or redacted. |
| Notification is tapped after unlock                                        | OnTrack opens the intended safe route for the test event and does not expose another user's data.                                 |

If an observed title or body differs from MN-D01, record the exact text and treat
that as a failure even if it happens to look harmless. The current push builder
uses the notification message as its body, so delivery alone is not proof that
the approved lock-screen copy was used.

## Physical-device rerun procedure

### 1. Record the test target

Use an actual Android phone. Before starting, record:

- manufacturer and model;
- Android version and security patch level;
- Chrome version;
- whether testing the browser tab or installed PWA; and
- test date, time, and network.

Use the merge heads intended for release in both repositories and replace the
base commit values in this report if they have changed.

### 2. Prove the local stack first

Follow `docs/notifications/push-setup.md` and
`docs/notifications/testing-push-locally.md`.

1. Confirm the API has development VAPID keys and
   `PushNotificationService.configured?` returns `true`.
2. Confirm the web app, API, and `ngsw-worker.js` respond locally.
3. Receive a push in a supported desktop browser before adding the phone. This
   isolates server and event problems from the mobile network path.
4. Record subscription rows before the phone subscribes. Do not copy complete
   endpoint URLs or keys into the evidence.

### 3. Create a secure phone origin

1. Start one HTTPS tunnel to the web app on port 4200, following the documented
   tunnel procedure.
2. Add only the generated tunnel hostname to the Angular dev server's allowed
   hosts and to Rails development hosts, then recreate or restart the affected
   services as documented.
3. Open the HTTPS URL on the phone and verify that the app and API load.
4. Confirm on the phone that `window.isSecureContext` is `true` and that
   `serviceWorker` exists in `navigator`.

Do not continue from a plain `http://192.168…` LAN URL. It can render the app but
cannot produce a valid Push API test.

### 4. Install, grant permission, and subscribe

1. In Chrome on the phone, install OnTrack to the home screen and launch the
   installed app.
2. Use a seeded, synthetic student account and wait for the service worker to
   register.
3. Check Android **Settings → Apps → Chrome → Notifications** and the site's
   notification permission. Both must allow notifications.
4. Temporarily configure the lock screen to show notification content, and turn
   off Focus or Do Not Disturb for the observation.
5. Use OnTrack's push opt-in control and accept the browser permission prompt.
6. Confirm that exactly one new or updated API subscription row belongs to the
   test user. Record only the row ID and endpoint host, not the full endpoint or
   cryptographic keys.

### 5. Deliver a real event while locked

1. Choose a v1 event covered by MN-D01 and record its approved title and body in
   the test notes.
2. Put the installed PWA in the background and lock the phone.
3. From a separate synthetic actor account, trigger the event through the normal
   OnTrack workflow. Do not send a hand-built push directly to the endpoint.
4. Record the trigger time, event type, recipient, and sanitized notification ID.
5. Wait for the notification and record its arrival time and latency.

### 6. Inspect and photograph the lock screen

1. Photograph the physical phone showing the collapsed notification on the lock
   screen.
2. Expand the notification and check that no additional private text appears.
3. Transcribe the exact visible title and body, including any truncation.
4. Compare both lines character-for-character with MN-D01.
5. Before attaching the photo, remove or redact unrelated notifications and
   personal or device-identifying details. Do not redact the OnTrack wording that
   is being reviewed.

### 7. Verify the tap route

1. Tap the notification and unlock the phone if prompted.
2. Record the final OnTrack route and page heading.
3. Confirm it is the intended destination for the event, is inside OnTrack, and
   shows only data available to the recipient.
4. Capture a sanitized screenshot of the destination after navigation.

If delivery, wording, privacy, or routing fails, preserve the sanitized evidence
and raise a separate defect with the phone/browser versions and reproducible
steps. Do not mark MN-Q02 passed merely because a subscription row was created.

### 8. Clean up

Revoke the test subscription, verify its API row is removed or invalidated, stop
the public tunnel, restore temporary host allowlists, and restore the phone's
lock-screen privacy settings.

## Evidence required to close MN-Q02

- [ ] Physical Android phone manufacturer and model.
- [ ] Android and Chrome versions.
- [ ] API and web commit SHAs actually tested.
- [ ] HTTPS origin and secure-context/service-worker checks.
- [ ] Sanitized subscription row before/after evidence.
- [ ] Event type, trigger time, arrival time, and delivery latency.
- [ ] Exact observed notification title and body.
- [ ] Explicit comparison with MN-D01.
- [ ] Privacy review of collapsed and expanded lock-screen views.
- [ ] Photo of the notification on the real Android lock screen.
- [ ] Tap destination route and sanitized destination screenshot.
- [ ] Cleanup confirmation.

None of the real-device evidence boxes are checked in this run.
