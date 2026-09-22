# Contributing to notifications

Start with the [API contributor guide](../../CONTRIBUTING.md) for setup,
repositories, branches, commits, tests and review. All three team repositories
use `11.0.x` for integration; open ticket pull requests against that branch.
This page contains the additional rules for email and mobile notifications.

For production diagnosis and queue operations, use the [runbook](RUNBOOK.md).

## The one domain rule: channel delivery belongs in Sidekiq

`NotificationService.notify` persists the in-app record, then queues separate
ID-only email and push jobs. Sidekiq workers reload the notification and perform
provider network I/O; a request only waits for the short Redis hand-offs. Both
jobs avoid the general-purpose `default` queue: email uses `mailers` and Web Push
uses `notifications`. Every deployed environment that should deliver
notifications must run a Sidekiq worker for both channel queues.

Email is queued by `Notification`'s creation `after_commit` hook, so a job
cannot read an uncommitted notification. `delivered_at` tracks the push queue
hand-off, not provider receipt. A failed push hand-off remains retryable.
Delivery is at-least-once: channel jobs take stable IDs and must tolerate retries.

Both channel jobs must raise when their notification id is not yet visible.
Producers can run inside wider database transactions, so a fast worker may read
before commit; treating that lookup as a successful no-op permanently loses the
channel. Push provider failures are attempted across all registered browsers
and then raised as an aggregate error so Sidekiq's retry policy is effective.

**Never loop over a whole cohort and call `NotificationService.notify` directly
from a web request.** Even without provider I/O, that would create one record
and make two queue round trips per recipient before the request can finish. The
current new-task and due-date events avoid that by enqueueing
`NewTaskAvailableNotificationJob` and `TaskDueDateChangedNotificationJob`; group
CSV import suppresses notifications. Follow those current patterns rather than
reintroducing request-path fan-out.

So before you wire an event to a hook, ask who it reaches when the hook fires in
the worst case, not the normal case. Three separate tickets have hit this
independently. If the answer is "everyone in the unit", inspect the existing
fan-out jobs and talk to the lead before you build it.

Two related habits worth having:

- **Never notify somebody about their own action.** Check the actor against the
  recipient.
- **Look at every caller of the method you are hooking, not just the obvious
  one.** `add_member` looks like a student joining a group. It is also called by
  tutorial changes, enrolment deletion and CSV import.

---

## Documentation

All notification documentation lives in **one** place:
`doubtfire-api/docs/notifications/`. Do not start a new folder, and do not put it
in `doubtfire-web`.

For general documents, use lowercase, hyphenated names with no dates and one file
per subject: `push-setup.md`, not `PushSetup_2026-08-14.md`. Event documents are
the exception: their filename is the exact lower-snake-case event passed to
`NotificationService.notify`, for example `task_comment_created.md`.

| What you are writing | Where it goes |
|---|---|
| An event | `docs/notifications/events/<event_name>.md` |
| Anything else | `docs/notifications/<subject>.md` |

**For an event, copy `docs/notifications/events/_template.md` and fill in the
eight field table.** It is not optional formatting. The table is what lets
somebody read the recipient and the preference gate without opening the code,
and it is what the security review tickets read.

Worked examples to copy rather than invent:

- `docs/notifications/events/task_comment_created.md` — the model event doc
- `docs/notifications/events/_template.md` — the eight fields
- `docs/notifications/push-setup.md` — VAPID keys and payloads
- `docs/notifications/testing-push-locally.md` — read this before you try to
  test push on a phone

**Push does not work on a phone over your LAN address.** A phone on your wifi
hitting `http://192.168.x.x:4200` is not a secure context, so the browser hides
the push API entirely and the opt-in button greys out. `localhost` is fine
without HTTPS. A phone is not localhost. You need a tunnel, and
`testing-push-locally.md` has the commands. On iOS there is a second step, you
have to Add to Home Screen and open it from the icon.

If somebody asks you a question this page does not answer, the answer goes in
here, not just in a reply.
