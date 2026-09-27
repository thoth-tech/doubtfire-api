# Notification delivery operations

## Email outcomes and retry

`Notification.email_delivery_state` records `pending`, `delivered`, `retrying`,
`failed`, `queue_failed`, `suppressed` or `throttled`. Historical rows are
`untracked`: their past SMTP outcome cannot be reconstructed. Attempt count,
SMTP acceptance time and exception class are persisted without addresses,
message content or SMTP response text. SMTP acceptance does not prove inbox
placement or capture a later bounce.

Primary mail uses the existing `mailers` Sidekiq queue with three retries
(four total attempts). Transient failures use Sidekiq's exponential backoff
with jitter. SMTP fatal/syntax errors (5xx permanent failures) go immediately
to the dead set. Exhausted retries persist `failed`, even after the dead set is
cleared. Deleted notifications are skipped; the after-commit enqueue prevents
a worker observing a not-yet-committed row. Opt-out and the configured mail-delivery switch are checked again at delivery;
disabled mail is recorded as `suppressed`, never `delivered`. Notification mailers
raise transport errors even when development mail normally swallows them.

```sh
bundle exec rake notifications:delivery_counts
NOTIFICATION_ID=123 bundle exec rake notifications:retry_email
```

Investigate and correct the recipient/configuration first. The retry task only
accepts `failed` or `queue_failed` records. Successful delivery is guarded by a
row lock and persisted completion marker. SMTP cannot provide exactly-once
delivery: a process crash after SMTP acceptance and before the database update
can still duplicate a message. Additional verified-address copies retain their
independent audit/retry lifecycle so a copy failure never repeats primary mail.

## Cohort and recipient limits

| Variable | Default | Meaning |
| --- | --- | --- |
| `DOUBTFIRE_NOTIFICATION_FANOUT_LIMIT` | 500 | Maximum candidate recipients without explicit operator override |
| `DOUBTFIRE_NOTIFICATION_RECIPIENT_LIMIT` | 30 | Maximum external notification hand-offs per recipient per window |
| `DOUBTFIRE_NOTIFICATION_RECIPIENT_WINDOW_SECONDS` | 3600 | Rolling quota window |

All values must be positive integers. Fanout counts are conservative candidate
project counts before detailed eligibility/preferences; they may overcount but
cannot undercount the candidate cohort. `notifications.fanout_limit` records
event, trigger id, candidate count, limit and admission decision. No names,
addresses or message bodies are logged. The recipient row lock serializes
quota reservations across concurrent event producers. Recipient, quota and
deduplication lookups use current locking reads even within an older caller
transaction. MariaDB versions that expose `innodb_snapshot_isolation` can reject
both those reads and the notification insert's foreign-key locks when a
recipient was updated after the caller's snapshot. During reservation only,
the connection temporarily disables that snapshot-conflict check and restores
its previous value before the surrounding workflow resumes, including on
exceptions. Row locks, foreign-key constraints and outer rollback remain in
force; ordinary MySQL is unchanged. Outside that reservation block, explicit
current reads use a statement-only override. An existing event's pending push
handoff is retried after the caller commits, preventing a retry from updating
an unseen row. In-app records remain available for throttled events, with no
push/email queued.

The compatibility setting follows MariaDB's documented dynamic session scope:
[InnoDB snapshot isolation](https://mariadb.com/docs/server/server-usage/storage-engines/innodb/innodb-system-variables#innodb_snapshot_isolation).
It is not a global database setting or a change to the deployment's default
transaction isolation.

An operator can deliberately rerun a verified cohort from Rails console, for
example `NewTaskAvailableNotificationJob.perform_async(task_definition_id, true)`.
The due-date job accepts its override as the fifth argument after change id;
retain the original change id to preserve deduplication. Scheduled due-soon and
availability sweeps accept a single boolean argument. Never enable an override
from an untrusted request parameter. Inspect recipient counts before use.

## VAPID secrets and rotation

Production API and worker boot require a matching P-256 VAPID public/private
pair. Development with both unset disables push. Invalid/partial keys fail
with a diagnostic naming the configuration, never the key material. Only the
public key appears on the authenticated settings response. Inject the private
key at runtime from the deployment's secret manager; never put it in Git,
Docker build arguments, image layers, support tickets or logs.

Rotation changes the application-server key. Existing subscriptions remain
bound to the old key and cannot be used with the replacement pair. Treat a
leaked private key as compromised immediately; do not keep it for convenience.

1. Generate a fresh pair in the controlled deployment environment using
   `WebPush.generate_key`; store it directly in the secret manager, without
   printing the private value to CI output or saving it in the repository.
2. Stage both values together and verify startup in a private environment.
3. Pause the push worker, deploy the pair to API and every worker, and restart
   them consistently. A mixed pair or mixed rollout produces failed deliveries.
4. In a controlled Rails console, invalidate old rows with
   `PushSubscription.delete_all`. This deletes subscriptions, not notifications.
5. Resume the worker and instruct users to open notification settings and
   re-enable push. The MN-C05 client resubscription flow is required; an old
   browser registration may need to be unsubscribed before it can be recreated.
6. Verify an authenticated subscription and a synthetic notification on each
   supported browser. Record only key version identifiers, never private values.

Repository/image/log scanning must be performed against the actual deployed
secret and built release by its owner; source review cannot attest to all
historic image layers or external logs. The repository's Docker ignore rules
exclude local `.env` files and key files. No real production secret was used
for this change's synthetic validation.

## Structured operation logs

`projects.index` emits once per authenticated collection request: `user_id`,
`include_task_definitions`, `include_inactive`, `project_count` and
`task_definition_count`. The latter counts definitions already preloaded for
returned projects, so it does not issue a second database query. Summary-only
responses report zero definitions. Use it alongside normal request duration
to compare dashboard and summary traffic; it does not log task contents.

`units.bulk_withdraw` records actor `user_id`, `unit_id`, row/result counts and
successfully withdrawn `project_ids`. `units.csv_export` records actor and unit.
Ids avoid duplicating student names/emails into logs. The JSON id list grows
linearly (300 numeric ids are typically a few kilobytes); configure log storage
to preserve complete lines, because truncation loses recovery evidence. Denied
requests do not produce a success audit event.
