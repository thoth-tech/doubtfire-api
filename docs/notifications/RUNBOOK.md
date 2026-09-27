# Notifications production runbook

Scope: the `11.0.x` API and the production stack in
[`doubtfire-deploy`](https://github.com/ontrack-features-t2-2026/doubtfire-deploy/blob/11.0.x/production/docker-compose.yml).
Commands below run from that repository's `production/` directory and use its
existing private `.env.production`. Confirm the environment before operating.
Do not copy production secrets or student content into incident reports.

## Stop delivery first

**There is no global notification kill switch or per-channel runtime toggle in
this revision.** `NotificationService` still creates in-app records. Stopping
Sidekiq contains queued email/push delivery without building a new image:

```sh
docker compose --env-file .env.production stop -t 60 sidekiq
```

This stops **all** work on that service, including `submissions` and `default`.
Check for separately managed workers before relying on it. In-flight messages
may already have reached their provider. New requests can continue queueing
work; monitor Redis capacity. This is a temporary containment action, not a
permanent opt-out or a way to retract email/push already delivered.

For email-only containment, production supports `DF_MAIL_PERFORM_DELIVERIES=no`.
Set it in the private environment file and recreate both API and worker:

```sh
docker compose --env-file .env.production up -d --no-deps --force-recreate apiserver sidekiq
```

This affects **all Rails mail**, including non-notification mail. Jobs consumed
while delivery is disabled succeed without sending; they are not saved for
later replay. Keep workers stopped instead when delivery must be retained.
A Rails console assignment changes only that console process. A plain Docker
`restart` does not load changed environment values.

For push-only containment there is no supported production toggle. Removing
VAPID keys makes delivery a no-op in API code, but production validation requires
those keys and doing this would consume queued pushes without sending. Do not
use key rotation as a delivery pause. Keep the worker stopped until an approved
queue configuration or runtime control is available.

Restore a stopped service with `docker compose --env-file .env.production start
sidekiq` only after reviewing queued work and the original failure. Restoring
email requires setting `DF_MAIL_PERFORM_DELIVERIES=yes` and recreating the
processes again. No source change or image rebuild is needed for these actions.

## Find the failing stage

A successful API response is not proof of email or push delivery.

1. Check API/worker/Redis health with
   `docker compose --env-file .env.production ps` and worker logs with
   `docker compose --env-file .env.production logs --since 15m sidekiq`.
2. Use the authenticated user's notification list to verify the in-app record.
   Category preferences can suppress record creation entirely.
3. Check queues, retries and workers using the read-only console commands below.
4. A `NotificationEmailJob` runs on `mailers`; a
   `PushNotificationDeliveryJob` runs on `notifications`. Both retry three times.
   The optional additional-address copy has a separate delivery job.
5. After a queue accepts a push job, `Notification.delivered_at` is set. It is a
   **push hand-off timestamp**, not an SMTP receipt, push receipt or read receipt.
   Email is queued after the notification creation transaction commits.

Open the console in the API process, which uses the same Redis as the worker:

```sh
docker compose --env-file .env.production exec apiserver bundle exec rails console
```

Then inspect aggregate metadata only:

```ruby
require 'sidekiq/api'
%w[mailers notifications submissions default].each do |name|
  queue = Sidekiq::Queue.new(name)
  puts({ queue: name, depth: queue.size, oldest_seconds: queue.latency }.inspect)
end
puts({ retry: Sidekiq::RetrySet.new.size,
       scheduled: Sidekiq::ScheduledSet.new.size,
       dead: Sidekiq::DeadSet.new.size }.inspect)
Sidekiq::ProcessSet.new.each do |process|
  puts({ identity: process.identity, busy: process['busy'],
         concurrency: process['concurrency'], queues: process['queues'] }.inspect)
end
```

Take two snapshots a minute apart. Falling depth/latency with busy workers
indicates progress. Growing latency with no process consuming the named queue
indicates a missing worker/queue configuration. Busy workers plus provider
errors/retries indicate slow or failing delivery; inspect SMTP/push responses
before increasing concurrency. Size alone cannot distinguish stuck from slow.
Production consumes queues in strict priority order: `mailers`, `notifications`,
`submissions`, `default`; a mail backlog can delay everything below it.

## Drain, retry or discard

To drain, stop the event source that caused the burst (for example the import),
fix the provider or worker issue, and let the normal worker process queued work.
Watch depth, latency and retry/dead counts until stable. A continuously active
cohort can prevent an empty queue. Increasing worker concurrency requires
checking database pool, memory and provider limits first.

To stop taking new work while finishing in-flight jobs, the console can quiet
workers with `Sidekiq::ProcessSet.new.each(&:quiet!)`. This applies to all
Sidekiq processes using that Redis namespace. It does not drain waiting jobs;
restart workers when ready to resume. Do not use `Queue#clear`, `RetrySet#clear`
or Redis `FLUSHDB` as incident recovery.

Inspect one known job ID without printing its arguments or exception message:

```ruby
jid = 'replace-with-the-job-id-from-the-incident'
job = Sidekiq::RetrySet.new.find_job(jid)
puts({ jid: job&.jid, klass: job&.klass, queue: job&.queue,
       error_class: job&.item&.fetch('error_class', nil),
       attempts: job&.item&.fetch('retry_count', nil) }.inspect)
```

After the cause is fixed, `job.retry` retries that one job immediately. Delivery
is at-least-once; confirm whether the provider already accepted it, since a
partial failure can duplicate delivery. Do not replay a whole cohort blindly.

For a confirmed poisoned job, record its JID/class/queue, reason for discard and
whether a replacement notification is required in the incident record. Check
it is not currently executing. Select the exact entry from `RetrySet`,
`DeadSet`, `ScheduledSet` or its named `Queue`, then call `job.delete` only on
that entry. Deletion permanently loses that pending attempt. Do not delete the
`Notification` database record to clear a queue: email jobs skip missing records,
while push jobs raise and retry a missing record. Redis iteration races with workers, so pause the
affected worker before selecting/deleting and confirm the JID is absent after.

## Mail deliverability and ownership

Check in this order:

- Was an in-app record created, and does the recipient still permit that category?
- Is `mailers` being consumed? Did the job enter retry/dead after an SMTP error?
- Is `DF_MAIL_PERFORM_DELIVERIES` exactly `yes`, and is delivery method `smtp`?
- Are SMTP host, port, TLS, authentication and sender domain correct? Compare
  deployed configuration privately; never print passwords into a report.
- Does the provider show accepted, deferred, bounced or rejected delivery?
  Check the mailbox spam folder after acceptance. An accepted SMTP transaction
  does not prove inbox arrival.
- Ask the institution's **mail/DNS administrator** to check SPF, DKIM signing,
  DMARC alignment and provider rejection diagnostics for the configured sender.
  The application team owns queue/config diagnosis; the institution controls DNS.

No named institutional DNS owner or escalation address is recorded in these
repositories. Before handover, the deployment owner must record that contact
in the private operations directory, together with the SMTP provider contact
and incident escalation route. This runbook cannot establish ownership from a
repository alone. Do not invent a person or edit DNS during routine diagnosis.
Follow the [email acceptance procedure](email-acceptance.md) for exact
configuration checks, a controlled single-recipient trial and evidence required
to close NPR-Q01. Repository tests do not prove mailbox placement.

## Push and VAPID rotation

Follow [push setup: keys](push-setup.md#the-keys) for the existing rotation
procedure and subscription invalidation requirement; do not rotate to solve a
queue backlog. Coordinate the change across API and workers and check the
[production deployment procedure](https://github.com/ontrack-features-t2-2026/doubtfire-deploy/blob/11.0.x/DEPLOYING.md)
for environment validation/recreation. The public key is public; the private
key stays in the secret store.

For diagnosis, verify keys are configured, the intended user has a browser
subscription, notification permission is granted, and the worker consumes
`notifications`. 404/410 subscription responses remove stale registrations;
other provider errors are retained and raised for retry. Check
[push failure handling](push-setup.md#failure-handling) and
[phone testing](testing-push-locally.md) before assuming the provider is down.

## Fan-out and deliberate cohort messages

The default cohort ceiling is 500 candidate recipients; the default per-recipient
quota is 30 external notification hand-offs per rolling 3,600 seconds. The
[delivery operations guide](delivery-operations.md#cohort-and-recipient-limits)
defines the three environment settings, protected event producers, current-row
locking and deliberate operator overrides. A rejected cohort logs
`notifications.fanout_limit`; a recipient over quota retains a `throttled`
in-app record and receives no external channel hand-off.

Current mitigations are explicit background fan-out jobs, recipient eligibility,
category preferences, duplicate keys and suppression of internal group moves.
See the [recipient amplification review](reviews/recipient_amplification_risk.md)
for the reviewed risks, and current [event documentation](events/README.md) for
recipient rules. That historical review includes planned events; current code
and event docs take precedence.

For a genuine all-cohort communication, agree the recipient scope and expected
count with the unit owner, review the communication rule, run a small test in
staging, and monitor channel backlogs/provider quotas while executing. Use only
the documented producer-specific override after reviewing the count; keep the
same event/change identity for deduplication. Do not edit individual users'
preferences or disable duplicate protection. The
[cohort benchmark](cohort-load-testing.md) exercises the delivery service
directly and does not authorize a larger production ceiling.

## Failure modes recorded in this repository

These are documented defects/setup failures, not a claim that this author
observed production incidents. Dates, impact and incident owners are not
available in the repository.

| Symptom | Recorded cause and recovery | Evidence |
| --- | --- | --- |
| Queue accepts email/push but nothing arrives | Worker consumed `default` only; configure `mailers` and `notifications` | [`config/sidekiq.yml`](../../config/sidekiq.yml) explains the fixed silent failure |
| Phone cannot enable push over a LAN URL | Browser requires a secure context; use HTTPS and iOS Home Screen flow | [Phone testing](testing-push-locally.md) |
| Development email appears missing | Without SMTP, mail is a file under the deploy mount, not the API checkout | [Development config](../../config/environments/development.rb) |
| Plain-text communication email contains `%>` | Nested ERB comment ended early; restore real greeting/sign-off and regression coverage | [Mailer regression](../../test/mailers/communications_mailer_test.rb), fixed by `42f7373191bb0b6686e0d2d4ee71cc3a2f814f80` |

## Handover verification still required

The repository deliverable is this runbook. Production sign-off additionally
requires the missing runtime controls/fan-out limits, a named private escalation
contact, and an independent operator dry-run. No such dry-run is claimed here.

In staging with mail captured and no real recipients, have someone outside the
notifications team diagnose a paused worker using only this guide. Record the
starting symptom, commands, diagnosis, recovery, operator and confusing steps.
Fold their feedback into a PR. Keep operational evidence private if it includes
addresses, message contents or secrets.
