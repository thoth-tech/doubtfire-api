# MN-D05 – v2 Push Lock-Screen Wording

## Decision

Use the configured product name as the title for every v2 push notification.
The current OnTrack deployment therefore shows `OnTrack` (7 characters).
Keep the body separate from the richer email and in-app message so a locked
device never exposes details that are only needed after the recipient opens
OnTrack.

## Approved wording

| Ticket and event                       | Event name                   | Push title              | Push body                                                              |                                         Body length | Privacy and email alignment                                                                                                                                                                                 |
| -------------------------------------- | ---------------------------- | ----------------------- | ---------------------------------------------------------------------- | --------------------------------------------------: | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| EN-V01 – Task due date changed         | `task_due_date_changed`      | Configured product name | `The due date for {{task_abbreviation}} in {{unit_code}} has changed.` | 34 + identifier lengths; 46 for `1.1P` / `COS10001` | Says that the due date changed without exposing the old or new date, a student, progress, or assessment content. The email can direct the student to the authenticated task for the new date.               |
| EN-V02 – New task available            | `new_task_available`         | Configured product name | `A new task is available: {{task_abbreviation}} in {{unit_code}}.`     | 30 + identifier lengths; 42 for `1.1P` / `COS10001` | Identifies the available task without a person, result, feedback, or task content. It has the same meaning as the richer email and task link.                                                               |
| EN-V03 – Task due soon                 | `task_due_soon`              | Configured product name | `{{task_abbreviation}} in {{unit_code}} is due soon.`                  | 17 + identifier lengths; 29 for `1.1P` / `COS10001` | Gives a neutral reminder without an exact deadline, progress state, mark, or feedback. The email can direct the student to the authenticated task for details.                                              |
| EN-V04 – Tutorial changed              | `tutorial_changed`           | Configured product name | `Your tutorial details changed.`                                       |                                                  30 | Deliberately omits the tutorial label, unit, meeting day, and meeting time. It preserves the EN-D05 meaning while leaving the new schedule to the richer email and authenticated unit page.                 |
| EN-V05 – Group membership changed      | `group_membership_changed`   | Configured product name | `Your group membership changed.`                                       |                                                  30 | Covers both the added and removed email variants without exposing the free-form group name, unit, other members, or the direction of the change.                                                            |
| EN-V06 – Task submitted for marking    | `task_submitted`             | Configured product name | `A task is ready for marking.`                                         |                                                  28 | This tutor-facing body intentionally omits the student's name and the potentially free-form task name. The EN-D06 email can identify the student and task for the assigned tutor; the lock screen must not. |
| EN-V07 – Portfolio submission received | `portfolio_received`         | Configured product name | `Your portfolio submission was received.`                              |                                                  39 | Preserves the EN-D06 receipt meaning without exposing the exact submission time or timezone. The richer receipt email remains the source for those details.                                                 |
| EN-V08 – Discussion prompt ready       | `discussion_request_created` | Configured product name | `A discussion prompt is ready for you.`                                |                                                  37 | Omits the tutor, task, unit, audio, and prompt content. It matches the proposed discussion-prompt event and does not falsely claim that a discussion was booked.                                            |

Character counts include spaces and punctuation. The three example counts use
the identifiers already exercised by the push payload tests.

## Length and truncation

`PushNotificationService::MAX_BODY_LENGTH` limits the API body to 400
characters. That ceiling protects the Web Push payload; it is not a display
guarantee. Android, iOS, desktop browsers, device settings, font size and
notification layout can all truncate earlier, at different points.

The fixed bodies are between 28 and 39 characters. EN-V01 to EN-V03 retain the
existing concise task abbreviation and unit code. Their exact length varies
with those identifiers, so the essential event wording must remain concise and
no private information may be placed later in the body in the hope that it
will be hidden by truncation.

## Lock-screen privacy rule

Assume the device is locked, face up and visible to someone other than the
recipient. A push title or body must not contain:

- a student, staff member, or other person's name;
- marks, grades, results, progress, feedback, comments or submission content;
- free-form group, task, tutorial, prompt or uploaded content;
- an exact class schedule or action timestamp unless separately approved for
  lock-screen display.

Task abbreviations and unit codes remain in EN-V01 to EN-V03 because the
existing lock-screen review classified those bounded academic identifiers as
acceptable for these events. The conservative EN-V04 and EN-V07 decisions
avoid extending that approval to schedule metadata or exact submission times.

## Email and in-app separation

The approved push bodies describe the same event as the EN-D05 and EN-D06
email copy but intentionally say less:

- EN-V04 email can give the new tutorial schedule; push only says it changed.
- EN-V05 email can explain whether the student joined or left a named group;
  push only says the membership changed.
- EN-V06 email can identify the student and task to the assigned tutor; push
  only says work is ready.
- EN-V07 email can act as a timestamped receipt; push only confirms receipt.

Changing `Notification#message` would also remove useful detail from email and
the in-app notification. The MN-S04 implementation therefore applies
`PushNotificationService::LOCK_SCREEN_BODY_OVERRIDES` for `tutorial_changed`,
`group_membership_changed`, `task_submitted` and `portfolio_received` while
leaving the stored message and richer channels unchanged. EN-V01 to EN-V03 and
the rescoped EN-V08 body already match the approved lock-screen wording.

## EN-V08 scope caveat

OnTrack currently has no discussion-booking or appointment record. The EN-V08
candidate branch instead raises `discussion_request_created` when a tutor's
audio discussion prompt is ready. This wording is approved only for that
rescope. A future real booking event needs its own wording and lock-screen
review; it must not reuse this event name or claim that a prompt is a booking.

At the time of this review, EN-V04, EN-V06, EN-V07 and EN-V08 were candidate
branches rather than part of `feature/notifications`. The exact event-name
mapping above is the contract those branches must retain when they merge.

## Documentation follow-up

`docs/notifications/events/_template.md` currently records email copy but has
no home for channel-specific push wording. Add `Push title` and `Push body`
fields to that template under EN-D03 so each future event is reviewed before it
inherits Web Push delivery. This ticket records the recommendation but does
not change the shared template.
