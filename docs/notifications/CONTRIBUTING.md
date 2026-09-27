# Contributing to notifications

Start with the [API contributor guide](../../CONTRIBUTING.md) for setup,
repositories, branches, commits, tests and review. All three team repositories
use `11.0.x` for integration; open ticket pull requests against that branch.
The former `feature/notifications` branch is historical. Check current code and
existing PRs before implementing an old ticket. The standing branch currency
rule is in [DECISIONS.md](DECISIONS.md).

For production diagnosis and queue operations, use the [runbook](RUNBOOK.md)
and [delivery operations guide](delivery-operations.md).

## Channel delivery belongs in Sidekiq

`NotificationService.notify` persists the in-app record, then queues separate
ID-only email and push jobs. Sidekiq workers reload the notification and perform
provider network I/O; a request only waits for the short Redis hand-offs. Both
jobs avoid the general-purpose `default` queue: email uses `mailers` and Web Push
uses `notifications`. Every deployed environment that should deliver
notifications must run a Sidekiq worker for both channel queues.

Email is queued by `Notification`'s creation `after_commit` hook, so a job
cannot read an uncommitted notification. A deleted record is a successful no-op
for that worker. `delivered_at` tracks the push queue hand-off, not provider
receipt; email outcomes have separate persisted fields. A failed push hand-off
remains retryable. Delivery is at-least-once: channel jobs take stable IDs,
recheck preferences and tolerate retries.

Push producers can run inside wider database transactions, so the push worker
must raise when its notification id is not yet visible. Push provider failures
are attempted across all registered browsers and then raised as an aggregate
error so Sidekiq's retry policy is effective.

**Never loop over a whole cohort and call `NotificationService.notify` directly
from a web request.** Even without provider I/O, that would create one record
and make two queue round trips per recipient before the request can finish. The
current new-task and due-date events avoid that by enqueueing
`NewTaskAvailableNotificationJob` and `TaskDueDateChangedNotificationJob`; group
CSV import suppresses notifications. Follow those current patterns.

Cohort jobs must use `NotificationDeliveryPolicy.fanout_allowed?` before
processing recipients. Use `NotificationService` rather than creating records
directly, so concurrent event producers share the recipient quota. Inspect the
worst-case audience and every caller of the hook: group membership changes can
also come from tutorial changes, enrolment deletion and CSV import. Never
notify somebody about their own action.

## Documentation

All notification documentation lives in `doubtfire-api/docs/notifications/`.
For general documents, use lowercase, hyphenated names with no dates and one
file per subject. Event filenames use the exact lower-snake-case event passed
to `NotificationService.notify`, for example `task_comment_created.md`.

| What you are writing | Where it goes |
| --- | --- |
| An event | `docs/notifications/events/<event_name>.md` |
| Anything else | `docs/notifications/<subject>.md` |

Copy [events/_template.md](events/_template.md) and fill in its eight-field
table for every event. Document the trigger, recipient eligibility, preference
category, deduplication identity and safe deep link. The worked example is
[events/task_comment_created.md](events/task_comment_created.md).
Keep final user-facing wording in its mail template or push implementation;
do not maintain a competing copy in documentation. Add recurring contributor
questions and their answers here.

## Tests and development

API tests use Minitest under `test/`, mirroring application paths. Use
`test/factories/notification_factory.rb` for events. Web tests use Vitest with
`<name>.spec.ts` next to the component.

```sh
# In the API development container with a populated, isolated test database:
bundle exec rails test test/sidekiq/notification_email_job_test.rb
# In the web repository:
npx vitest run src/app/api/services/notification.service.spec.ts
```

Follow the API contributor guide for Ruby, MariaDB and Redis setup. Test a
normal path, denied/invalid inputs and retries where relevant. Never populate
or clean a shared database while somebody else's tests are using it.

Development-only `DOUBTFIRE_NOTIFICATION_EMAIL_INLINE=true` permits Mailpit
email testing without a worker. It never enables inline production delivery.
Use synthetic users and redact credentials and student data in PR evidence.
Mailpit capture proves rendering, not inbox delivery. A browser unit test does
not prove that a physical phone displayed a push.

Read [push-setup.md](push-setup.md) and
[testing-push-locally.md](testing-push-locally.md) before testing on a phone.
A phone reaching `http://192.168.x.x:4200` over Wi-Fi is not in a secure context;
use the HTTPS tunnel described there. On iOS, also Add to Home Screen and open
the app from its icon.
