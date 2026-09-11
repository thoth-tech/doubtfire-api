# MN-Q02 – Android phone push verification

## Physical-device rerun — 28 August 2026

**THE OPERATING-SYSTEM DELIVERY AND TAP GATE PASSED.** A real Android phone
registered a fresh Web Push subscription, received an OnTrack notification, and
opened the installed OnTrack app when the notification was tapped. The recipient
then confirmed that the task feedback was present at the intended `1.1P`
destination. A final cold-launch rerun also crossed the sign-in screen and
resumed at the exact `1.1P` Feedback pane after authentication. This supersedes
the blocked 23 August attempt for the MN-MVP01 and ON-MVP01 physical-delivery
gate.

The run also exposed phone usability defects. The fixed 400 px task list left
the task and feedback panes off screen; the Task Planner button overlapped the
floating grade label; and the attachment target in the feedback composer was
partly outside the viewport. The navigation and sign-in fixes are merged in
`doubtfire-web` PRs 123 and 124. The 48 px composer controls are live and covered
by PR 126. These defects did not invalidate the OS delivery result, but resolving
them was necessary for the notification destination to be usable on the phone.

### Observed acceptance status

| Ticket check                                  | Result                          | Evidence                                                                                                                                 |
| --------------------------------------------- | ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Notification received on a real Android phone | **Met**                         | Recipient confirmed the OnTrack operating-system notification arrived after installing and launching the PWA.                            |
| Nothing private visible in notification copy  | **Met for observed copy**       | Visible body was `Andrew Cain commented on 1.1P in COS10001.`; the comment text, mark, grade, and tokens were absent.                    |
| Click navigates correctly                     | **Met**                         | Tap cold-launched OnTrack, crossed sign-in, and resumed at `COS10001` `1.1P` Feedback; recipient confirmed the new feedback was present. |
| Installed-app delivery path                   | **Met**                         | Delivery succeeded after installing from Chrome, launching the installed app, and cycling notification settings.                         |
| Lock-screen collapsed/expanded recording      | **Awaiting replacement upload** | The recipient is replacing the recording in the existing evidence location; final duration and SHA may change.                           |
| Device/browser inventory                      | **Not recorded**                | Manufacturer, Android version, and Chrome version still need to be transcribed from the device or recording.                             |

The final video checksum and device inventory are evidence-administration items;
they do not reverse the directly observed OS delivery and tap result. They must
be added before claiming that every MN-Q02 archival-evidence checkbox is closed.

### Exact run evidence

| Item                               | Observed value                                                                                  |
| ---------------------------------- | ----------------------------------------------------------------------------------------------- |
| Test date and timezone             | 28 August 2026, Australia/Melbourne                                                             |
| API release head at final delivery | `8cdccc7944f64b75f5f85952f02671dd96cf3f98`                                                      |
| API head after session follow-up   | `51d662850db15dabc710cf10972415553d03b761`                                                      |
| Web release head at final delivery | `fa3f50a6901c8ef82a0872d597757030d1bfb9fb`                                                      |
| Web head after usability follow-up | `024e12ee15e7c0309d36a621aff29b98bb4d8f6e`                                                      |
| Deploy head                        | `e791b57ba3e949e01285270f4bc0ea29fb23bb39`                                                      |
| HTTPS origin                       | Temporary `trycloudflare.com` tunnel; app, API, and service worker returned 200                 |
| Synthetic actor                    | `acain` / Andrew Cain                                                                           |
| Synthetic recipient                | `student_1`                                                                                     |
| Event                              | Tutor text comment on project 2, task definition 1 (`COS10001` `1.1P`)                          |
| Accepted task comment              | Comment 12, `Android auth-return proof — 2026-08-28 21:02:37 +1000`                             |
| Notification record                | Notification 11                                                                                 |
| Subscription                       | Row 2, endpoint host `fcm.googleapis.com`, refreshed at 19:42:36 AEST                           |
| Provider result                    | HTTP 201 `Created`; Sidekiq push job completed without exception at approximately 21:02:53 AEST |
| Visible title                      | `OnTrack`                                                                                       |
| Visible body                       | `Andrew Cain commented on 1.1P in COS10001.`                                                    |
| Intended route                     | `/projects/2/dashboard/1.1P/feedback`                                                           |
| Tap result                         | Installed OnTrack app opened sign-in when required, then resumed at the exact Feedback pane     |

The earlier accepted OS-delivery event was comment 5 / notification 5 at
09:30 AEST. Later diagnostic deliveries also returned HTTP 201 and were used to
isolate Android presentation, routing, and authentication state. The successful
device setup was: install OnTrack to the home screen, launch the installed app,
allow Android/browser notifications, and cycle the OnTrack notification controls
off and on once.

### Follow-up phone-layout and authentication verification

The primary navigation and feedback defects found by this rerun are merged in
`doubtfire-web` PR 123, `fix(dashboard): complete mobile navigation and feedback
routing`, at head `b9bc5abb9125d50251571ecf3f743c68398fd858` and merge commit
`3b7be9ffca5d563b25766bf4cf7487beb90897d7`.

- unread comment deep links open a full-width Feedback pane;
- Tasks, Details, and Feedback are explicit phone controls;
- the comment viewer and composer fit the phone viewport and keyboard;
- the narrow header no longer clips the profile control; and
- desktop split-pane behaviour is unchanged.

Live checks found no horizontal overflow at 360 or 430 px, and the targeted
dashboard/header suites, lint, typecheck, build, and GitHub CI passed.

PR 124, `fix(mobile): restore notification return and dashboard spacing`, is
merged at head `f3077f05e72ae6133ddefc447594549ba22cfebf` and merge commit
`0ba9fd703155190e1d64a804157a6f2f5bdf2170`.

- a protected destination survives refresh failure and sign-in in tab-scoped,
  expiring storage;
- successful password login resumed at `/projects/2/dashboard/1.1P/feedback`;
- the same one-shot handoff can cross a future same-tab SSO redirect;
- external, malformed, stale, and authentication-loop destinations are rejected;
  and
- at 390 px the planner button and grade field have 16 px separation, with the
  floating label beginning 9.25 px below the button.

The last physical-phone finding is covered by PR 126,
`fix(mobile): enlarge feedback composer actions`, at head
`f7cdb7b204ad03ba09b05530c022dd0b223faa52`. The same patch is running on the
live evidence origin as web head `024e12ee15e7c0309d36a621aff29b98bb4d8f6e`.

- attachment and microphone targets are each 48 by 48 px;
- they begin at x=8 and x=60 instead of x=-7.2 and x=16.8;
- both target centres hit the intended enabled button;
- the feedback input retains 270 px width; and
- the 390 px composer has no horizontal overflow.

The server-side refresh boundary found during the same cold-launch work is
covered by `doubtfire-api` PR 101, `fix(auth): renew refresh tokens before
expiry`, at head `51d662850db15dabc710cf10972415553d03b761`. The live evidence API
was restarted at that exact commit and returned HTTP 200 locally and through the
public origin. Expired and near-expiry refresh tokens now rotate, while tokens
outside the 12-hour renewal window are reused.

## Previous result — 23 August 2026

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
