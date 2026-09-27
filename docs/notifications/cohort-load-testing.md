# Cohort notification load testing

`script/benchmark_notifications.rb` provides a reproducible synthetic workload
against a real database and Redis queue. It seeds configurable synthetic users,
valid push subscription material, and a configurable opt-out mix, then compares
inline delivery with queued delivery and two concurrent events. Mail delivery
uses Rails' test transport; push delivery is stubbed at the provider boundary.
It records trigger-service time, queue drain time, total time, sampled queue
depth and Linux resident memory, and removes its synthetic users on completion.
Each mode asserts expected notifications, persisted `delivered` rows, email
attempts, Rails test emails, stubbed push calls and empty queues. Cleanup is
verified before a successful JSON result is emitted. Concurrent peak sampling
uses a mutex. Sampling after notification creation and each drained job adds
overhead that is included in the timings.

```sh
RAILS_ENV=test COHORT_SIZE=100 OPT_OUT_PERCENT=20 \
  BENCHMARK_SOURCE_REVISION="$(git rev-parse HEAD)" \
  BENCHMARK_RESULT_PATH=/tmp/notification-benchmark.json \
  bundle exec rails runner script/benchmark_notifications.rb
```

Use a dedicated populated test database and empty dedicated Redis database
(number 1 or higher). Never run alongside other workers using those queues.
The harness refuses production and nonempty delivery queues. It intentionally
uses only synthetic transports and `.invalid` email addresses.
It sets the recipient quota to 100 in this process; no recipient receives more
than four events across the three modes. It calls `NotificationService` directly,
bypassing cohort producer admission. A 1,000-user result does **not** imply that
the default 500-candidate ceiling permits that cohort in production.

Set `COHORT_SIZE` to the actual largest enrolment supplied by the institution,
then repeat with headroom and increasing sizes (record that enrolment as
`LARGEST_UNIT_ENROLMENT`). Keep the output and hardware/worker configuration with
the PR. Identify the size where the agreed latency or memory budget fails.
Do not describe a small local run as proof of production capacity.

The trigger measurement starts at `NotificationService`, so it excludes HTTP,
authentication and event-specific database eligibility queries. Queue drain is
one local worker and provider latency is synthetic. Production acceptance still
requires HTTP timing, the actual largest enrolment, representative worker
concurrency, transport latency, delivery-rate constraints and a measured
saturation point. Those institutional measurements are not fabricated here.

## Current 500- and 1,000-user results — 21 September 2026

Both cohorts completed with 20% opt-outs, all expected synthetic channel deliveries,
empty queues and verified fixture cleanup. Each single event reached 400/800
eligible users respectively; each two-event case produced 800/1,600 notifications,
emails and pushes. No real message left the test process. These are individual
samples under shared local load, not production capacity or an HTTP SLO result.

| Users | Mode | Trigger (s) | Drain (s) | Total (s) | Sampled queue peak | Sampled RSS (KiB) | Verified notifications / emails / pushes |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 500 | inline_baseline | 15.8606 | 0.0004 | 15.8610 | 2 | 334160 | 400 |
| 500 | queued | 6.6502 | 14.4861 | 21.1363 | 800 | 334624 | 400 |
| 500 | concurrent_queued | 31.9343 | 17.8731 | 49.8074 | 1600 | 349408 | 800 |
| 1000 | inline_baseline | 192.4294 | 0.0018 | 192.4313 | 2 | 338608 | 800 |
| 1000 | queued | 41.6023 | 27.7178 | 69.3201 | 1600 | 339112 | 800 |
| 1000 | concurrent_queued | 52.5015 | 51.7298 | 104.2313 | 3200 | 361544 | 1600 |

[Raw 500-user results](benchmark-results/2026-09-21/cohort-500.json),
[raw 1,000-user results](benchmark-results/2026-09-21/cohort-1000.json) and
[exact revisions, isolation, resource limits and reproduction commands](benchmark-results/2026-09-21/README.md)
are committed together. Runtime code is unchanged from `0fee2ba`; the harness
adds verified counts and synchronized sampling. The actual institutional maximum,
a real pre-queue comparison, HTTP latency and a saturation point remain unmeasured.

## Find the real cohort size without student data

An authorized deployment owner runs this read-only query in the deployed API.
It follows `Unit#active_projects` (`enrolled: true`) and the active unit scope
used by scheduled notification producers. Only counts are printed.

```sh
bundle exec rails runner - <<'RUBY'
counts = Project.joins(:unit).where(enrolled: true, units: { active: true })
                .group(:unit_id).count.values
puts({ active_units_with_enrolments: counts.length,
       largest_active_unit_enrolment: counts.max || 0 }.to_json)
RUBY
```

The owner confirms that active units cover the intended teaching period. The
registrar/unit owner supplies upcoming enrolments and forecast growth; a current
database maximum is not a forecast. Record the approved maximum in
`LARGEST_UNIT_ENROLMENT` when rerunning. A contributor need not know these values
or have production credentials. Obtain the staging URL and release configuration
from the hosting/deployment inventory, not guessed repository URLs.

## Finish institutional capacity acceptance (NPR-T01)

The deployment and service owners fill in these thresholds before testing.
An unknown threshold is an open acceptance input, not a pass.

| Input | Owner decision |
| --- | --- |
| Cohort and growth | Current/forecast maximum, teaching period, headroom |
| Event mix | Release, due-date change and reminders; burst/overlap frequency |
| HTTP budget | p95/p99 trigger latency, error rate and measurement window |
| Delivery budget | Maximum queue age/drain time, sustainable notifications/second |
| Resources | API/worker/DB CPU and memory, DB pool/connections, reserve |
| Transports | Worker count/concurrency, provider rate limits and sandbox latency |
| Saturation plan | Warm-up/repeat count, size/concurrency increments, stop conditions |

1. Create an isolated staging fixture with synthetic enrolled users, an active
   unit and task definitions at the approved maximum/opt-out mix. Include target
   grades, withdrawn enrolments and dates. Use approved provider sandboxes/sinks
   and controlled browser subscriptions. Verify every worker's transport boundary:
   the harness's in-process push stub does not affect a separate Sidekiq process.
   Never fan out to real students for a load test.
2. Measure the real authenticated convenor trigger routes:
   `POST /api/units/:unit_id/task_definitions/` creates a task release;
   `PUT /api/units/:unit_id/task_definitions/:id` with changed `task_def[due_date]`
   creates a due-date event. Capture HTTP duration/status in the load tool or
   reverse-proxy metrics. Fresh events need fresh fixture definitions/change
   identities; replaying an identity intentionally deduplicates and produces
   misleadingly cheap measurements. Preserve identities when testing retries.
3. Measure the event-specific eligibility/database work and worker queues. The
   routes enqueue `NewTaskAvailableNotificationJob` and
   `TaskDueDateChangedNotificationJob`. In the isolated fixture environment,
   scheduled events can be queued using
   `SendNewTaskAvailableNotificationsJob.perform_async` and
   `SendDueSoonRemindersJob.perform_async` in Rails console. These sweep every
   active unit, so never share a database with real students. Arrange fixture
   dates/markers to satisfy each job's eligibility/catch-up window, and verify
   expected eligible and opted-out counts before accepting timing.
4. Verify admission/rejection first. Above the configured ceiling, expect
   `notifications.fanout_limit` and no cohort delivery. A deliberate larger trial
   uses the producer-specific override in
   [delivery operations](delivery-operations.md#cohort-and-recipient-limits),
   records it and preserves the original event identity for retries. This does
   not demonstrate that normal requests bypass the limit.
5. Start the release's actual worker command. Record effective queues,
   `DF_SIDEKIQ_CONCURRENCY`, DB pool sizes and container limits. Capture queue
   depth/age, retry/dead counts, CPU/RSS and DB utilization at fixed intervals.
   Use `docker stats` or the deployment monitor for all services; the harness's
   RSS is one Ruby process, not the total memory footprint.
6. Repeat the same workload, then increase size/event overlap/worker concurrency
   using the agreed matrix. Include two distinct simultaneous events, peak burst
   and a controlled transient provider failure/recovery. Stop at the first
   agreed latency/error/memory/provider boundary and let queues drain. Record
   the last passing and first failing point; a run that never reaches a boundary
   cannot claim saturation.
7. Compare against a real pre-queue checkout under comparable fixture, hardware,
   cache and transport conditions. The parent of the email queue introduction
   (`67d9f92e`) is `564ff793f899e10fbfb4eaa80cfa3616da8e62ed`; source inspection
   confirms `NotificationService.notify` delivered both channels inline there.
   Create a separate detached worktree with
   `git worktree add --detach ../notification-prequeue-baseline 564ff793f899e10fbfb4eaa80cfa3616da8e62ed`,
   and use its own disposable database, locked dependencies and synthetic capture
   adapters. Adapt the measurement driver to that revision's schema/API rather
   than applying current migrations to it. The current harness's inline mode is
   a synchronous comparison on current code, **not** this historical measurement.
   Record p95/p99 over the agreed repeats, counts, drain/queue age, retries/failures,
   opt-outs, exact commands/revisions and acceptance decision.

Read-only queue snapshot in the selected staging API environment:

```sh
bundle exec rails runner - <<'RUBY'
require 'sidekiq/api'
queues = %w[mailers notifications default].to_h do |name|
  queue = Sidekiq::Queue.new(name)
  [name, { depth: queue.size, oldest_wait_seconds: queue.latency }]
end
puts({ queues: queues, retry_count: Sidekiq::RetrySet.new.size,
       dead_count: Sidekiq::DeadSet.new.size }.to_json)
RUBY
```

Institutional maximum, HTTP SLOs, real provider latency and saturation remain
unverified until these operator steps are executed and reviewed.

## Earlier harness smoke — 21 September 2026

A single smoke run completed with 40 synthetic recipients, 20% opted out, a
dedicated MariaDB 12.3 test database and Redis database 9. The API image was
`ontrack-unit-hub-release-preview-api:20260914` (Ruby 3.4.10, Rails 8.0.5.1).
These measurements used API source `e95bd592`, before the later rebase and
recipient-update compatibility fix; they are harness evidence, not a timing
claim for every subsequent API revision.
The Docker VM exposed 10 CPUs and 7.75 GiB memory; the API container had no
additional CPU or memory limit. Other local test containers shared that VM.

| Mode | Simultaneous events | Trigger service (s) | Queue drain (s) | Total (s) | Sampled queue peak | Sampled RSS (KiB) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Inline baseline | 1 | 2.2752 | 0.0003 | 2.2755 | 2 | 317024 |
| Queued | 1 | 0.1893 | 0.3195 | 0.5088 | 64 | 317096 |
| Concurrent queued | 2 | 0.2697 | 0.5048 | 0.7745 | 128 | 322320 |

Both delivery queues were empty afterward and all synthetic users were removed.
This verifies that the harness runs through opt-outs, two external channels and
concurrent events. These are single samples in the displayed order without a
warm-up, so cold-start and cache effects differ between modes. The inline mode
drains after each recipient through the same queue adapters; it is a synchronous
comparison within this harness, not a measurement of a historical application
version. No email or push message left the test process. The institution's
largest enrolment was unavailable, and this run establishes neither a supported
cohort limit nor production latency, throughput or saturation.
