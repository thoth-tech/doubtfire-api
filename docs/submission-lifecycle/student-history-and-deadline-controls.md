# Student history and deadline controls

Implementation for SLR-H02/H03 and SLR-E03/E04/E05, building on API PRs #94 and #135.

## Rule and policy boundary

This change preserves the rule already merged in #94: eligible Fix and Resubmit,
Discuss, Rediscuss or Demonstrate feedback near a fixed target date adds the
unit-configured weeks, once per submission round, capped by the task maximum and
special consideration. Flexible dates remain student managed. It does not
recalculate historical feedback.

The SLR-E01 PDF in web PR #249 explicitly says **Proposed – awaiting stakeholder
approval** and proposes seven calendar days from feedback with different repeated
feedback and flexible-date rules. That proposal is not an approved replacement
for #94. Reviewers should resolve that product decision separately; this PR does
not silently change the deployed calculation. The existing E02 DST and extension
regressions remain the executable specification for this change.

## Task setting

`resubmission_extensions_enabled` defaults to true for both existing and new
rows. The existing task-definition create/update authorization (`add_task_def`)
limits changes to convenors and administrators. Tutors, students and staff of
other units cannot update it. Disabling the setting only suppresses future
automatic extensions; it does not remove approved time or prevent a normal
extension request. The unit must still allow a positive number of resubmission
weeks and fixed dates.

The API stamps the authenticated actor and time of the latest explicit change in
`resubmission_extensions_changed_by_id` and `resubmission_extensions_changed_at`.
Those fields are not client writable and are not added to student responses.
Defaults applied by migration have no invented historical actor. This is latest
change attribution, not a general audit-log subsystem.

## Canonical deadline and delivery

Task responses expose `effective_deadline_date`, `effective_deadline` (the instant
at end of day anywhere on earth), `effective_deadline_reason` and
`effective_deadline_source_id`. Reasons are `standard_due_date`,
`approved_extension`, `post_feedback_extension` or `flexible_date`. The flexible
case is a planned submission date, not a newly imposed hard deadline.

The existing Webcal feed uses `effective_deadline_date` for its existing
`E-<task-definition-id>` all-day event. There is no new feed or second event.
Dates are read in the task campus time zone before converting to a civil date.

An applied extension reserves one `resubmission_deadline_changed` notification
through NotificationService with a database-enforced dedupe key based on the
extension record. Message text includes the new date and general reason, never
feedback, task titles or student names. The existing extension category and
email/push preferences remain authoritative. Delivery occurs after all enclosing
transactions commit. Row locking serializes simultaneous extension attempts;
the deadline, replay marker and notification reservation commit together.
Group members keep their existing individual Task records and each affected
student receives only their own deadline notification.

## Retained submission history

The student list contains safe metadata only: record id, numeric newest-first
version order, submission/archive timestamp, availability and a current flag.
The latest archive is current only when it is at least as recent as the latest
processing start and no newer archive is pending. Legacy data without that
processing timestamp falls back to the recorded submission date. The UI also
identifies the latest retained archive without assuming that it is current.

The original authorised download endpoint remains authoritative on every click.
Missing, removed and corrupt archives remain unavailable; their metadata is
retained where the row exists. HTTP 202 means archive creation is pending and
carries the existing retained versions. No unretained file is reconstructed and
no retention period changes. Group access remains tied to the student's own
historical Task; joining a group does not expose another member's old Task, and
leaving does not revoke archives retained on the student's own Task. Staff keep
the richer history response and existing comparison workflow.

## Verification

Run the focused API and existing policy/calendar packs:

```sh
bundle exec rails test test/models/submission_lifecycle_test.rb test/api/resubmission_setting_test.rb test/api/submission_history_access_test.rb
bundle exec rails test test/models/task_test.rb -n '/resubmission|daylight|extension|deadline/'
bundle exec rails test test/models/webcal_test.rb test/api/webcal_api_test.rb test/models/submission_history_test.rb
```

The paired web PR supplies the student view and unit-chair setting. External
stakeholder approval and real Google/Apple/Outlook refresh behavior are outside
this repository change; CAL-Q02 remains responsible for calendar-client checks.

The E05 trigger regression also found that `assess` skipped the declared
Discuss/Rediscuss/Demonstrate rule because those statuses took its completion
branch. The common eligibility check now runs after completion-date handling,
so every outcome declared by the existing rule reaches it.
