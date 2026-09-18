# MN-S04 – v2 push payload lock-screen sign-off

## Decision

**Sign-off status: APPROVED for the payload policy in this branch.**

All eight v2 event bodies are safe to display on a locked device. The four
events whose richer in-app messages contain a free-form name or precise
schedule data now use reviewed, event-keyed Web Push copy. Email and in-app
notifications retain their useful detail after sign-in.

This review covers the current EN-V01, EN-V02, EN-V03 and EN-V05
implementations on `feature/notifications`, plus the candidate EN-V04, EN-V06,
EN-V07 and EN-V08 branches. The candidate event branches had not merged when
the review was completed. Their sign-off depends on retaining the event names
recorded below so the lock-screen override is applied.

## Applied rule

A push notification must be safe when anyone near a locked phone can read it.
The visible title is the configured product name, **OnTrack** in this
deployment. The body must contain no person name, comment, feedback, mark,
grade, free-form label, task name, precise schedule, or exact action time unless
that field has received an explicit lock-screen privacy approval.

`PushNotificationService` still caps the body at 400 characters. Truncation is
a transport limit, not redaction. Safety comes from selecting reviewed copy
before truncation.

## Event findings

| Event                             | Event name                   | Final lock-screen body                                             | Finding  | Reason                                                                                          |
| --------------------------------- | ---------------------------- | ------------------------------------------------------------------ | -------- | ----------------------------------------------------------------------------------------------- |
| EN-V01 – Task due date changed    | `task_due_date_changed`      | `The due date for <task abbreviation> in <unit code> has changed.` | **Pass** | Bounded academic identifiers; no date, person, result, feedback, or free-form content.          |
| EN-V02 – New task available       | `new_task_available`         | `A new task is available: <task abbreviation> in <unit code>.`     | **Pass** | Bounded academic identifiers; no personal or assessment detail.                                 |
| EN-V03 – Task due soon            | `task_due_soon`              | `<task abbreviation> in <unit code> is due soon.`                  | **Pass** | No exact deadline or student-specific progress.                                                 |
| EN-V04 – Tutorial changed         | `tutorial_changed`           | `Your tutorial details changed.`                                   | **Pass** | The override omits the tutorial label, unit, meeting day, and meeting time.                     |
| EN-V05 – Group membership changed | `group_membership_changed`   | `Your group membership changed.`                                   | **Pass** | The override omits the free-form group name, unit, and add/remove direction.                    |
| EN-V06 – Submitted for marking    | `task_submitted`             | `A task is ready for marking.`                                     | **Pass** | The tutor sees no student name, task name, unit, or product interpolation on the lock screen.   |
| EN-V07 – Portfolio received       | `portfolio_received`         | `Your portfolio submission was received.`                          | **Pass** | The override omits the exact submission time and timezone while preserving the receipt meaning. |
| EN-V08 – Discussion prompt ready  | `discussion_request_created` | `A discussion prompt is ready for you.`                            | **Pass** | No tutor, student, task, unit, audio, or prompt content.                                        |

## How the unsafe payloads were corrected

`PushNotificationService::LOCK_SCREEN_BODY_OVERRIDES` owns the reviewed bodies
for EN-V04 through EN-V07. `payload_for` selects that copy by the persisted
event name before applying `MAX_BODY_LENGTH`.

This location is deliberate:

- `Notification#message` remains the rich in-app and email message.
- Web Push never receives the group name in EN-V05 or the student/task names in
  EN-V06.
- Rebuilding a payload from a persisted notification produces the same safe
  body; no transient caller argument can be lost or bypassed.
- Unrelated events continue to use their existing notification message.

Focused service tests construct every overridden event with a unique sensitive
canary and assert both the exact approved body and the canary's absence. The
EN-V05 model test separately proves that its email still contains the rich
message while its push body is generic.

## Payload fields outside the visible body

The payload also carries a collapse tag, `notification_id`, a validated
internal click route, and Angular's click action. The service worker does not
render these values as lock-screen text. The route allowlist still matters for
navigation safety, but a safe route is not being used as a substitute for safe
visible copy.

The encrypted payload transits a third-party push service operated by the
browser vendor. The reviewed bodies reveal only the broad event type. Endpoint
and encryption keys are transport metadata supplied separately to that service;
they are not copied into the notification JSON.

## Email and in-app consistency

The shorter push copy preserves the meaning of the richer EN-V05 and EN-V06
email/in-app messages without repeating private detail on a shared screen:

- EN-V05 still tells the signed-in student which membership changed.
- EN-V06 still tells the signed-in tutor which student and task are waiting.
- EN-V04 and EN-V07 keep schedule and receipt details in authenticated or email
  contexts while push communicates only that the event occurred.

This is intentional channel-specific copy, not a contradiction between
channels.

## Rule gaps and follow-up guardrails

The original rule named comments, feedback, marks, and grades but did not fully
classify free-form labels, schedule metadata, or exact action times. Apply these
additions going forward:

1. Treat every free-form value as unsafe for push by default.
2. Treat names and precise schedule/action timestamps as unsafe unless a
   documented privacy decision approves them.
3. Give email, in-app, and lock-screen copy separate fields in the event
   documentation template.
4. Add a negative payload test whenever an event's rich message contains a
   person name, free-form value, assessment detail, schedule, or exact time.
5. Re-run this review if any event name changes, because the override is keyed
   by that stable name.

## Sign-off checklist

- [x] Applied the MN-S02 lock-screen rule without weakening it.
- [x] Reviewed all eight v2 event bodies.
- [x] Reviewed the tutor-facing EN-V06 payload specifically.
- [x] Replaced unsafe V05 and V06 bodies with channel-specific copy.
- [x] Resolved V04 and V07 conservatively rather than exposing schedule/time
      metadata.
- [x] Preserved richer email and in-app meaning.
- [x] Added automated negative checks for every override.
- [x] Recorded the remaining rule gaps and follow-up guardrails.
