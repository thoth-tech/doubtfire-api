# Existing Email Audit

This document records email behaviour that already exists in OnTrack and the
shared email-delivery paths used by the v2 notification work. Its purpose is to
prevent new notification events from duplicating existing email behaviour or
accidentally sending multiple messages for the same action.

The audit covers both the API mailers and the existing communication subsystem
in the web application.

## Audit snapshot

This audit was checked against `feature/notifications` at commit
`09a61714425f12e1412da5b7a34f31f7ea5612dd` on 15 August 2026.

The primary reference for each send site is its class and method name. The
linked line ranges are pinned to the audited commit so later code changes do not
make the references point to unrelated code.

The audit can be reproduced with:

```bash
git grep -nE '\.deliver(_now|_later)?([^[:alnum:]_]|$)' \
  09a61714425f12e1412da5b7a34f31f7ea5612dd -- app lib \
  | grep -Ev 'PushNotificationService\.deliver|def (self\.)?deliver(_now|_later)?([^[:alnum:]_]|$)'
```

The command returned 21 direct email delivery call sites after the push
delivery call was excluded. Each result was manually checked to confirm that
it sends an email.

## API email send sites

A search of `doubtfire-api` for `.deliver`, `.deliver_now`, and
`.deliver_later` identified 21 real email send sites. Push notification service
calls and method definitions are not counted as email send sites.

| Existing email | Trigger / stable send-site reference | Recipient | Preference / guard |
| --- | --- | --- | --- |
| Turnitin error log | [`TurnItIn.handle_tii_error`](https://github.com/ontrack-features-t2-2026/doubtfire-api/blob/09a61714425f12e1412da5b7a34f31f7ea5612dd/app/helpers/turn_it_in.rb#L72-L80) – a Turnitin request returns HTTP 403 | Configured administrator/error-log address | Operational path; no user preference; attempted only for a 403 error |
| Task PDF failed – queued converter | [`PortfolioEvidence.process_new_to_pdf`](https://github.com/ontrack-features-t2-2026/doubtfire-api/blob/09a61714425f12e1412da5b7a34f31f7ea5612dd/app/models/portfolio_evidence.rb#L31-L75) – queued task PDF conversion reports a failure | Project student | `receive_task_notifications` |
| Weekly student summary | [`Project#send_weekly_status_email`](https://github.com/ontrack-features-t2-2026/doubtfire-api/blob/09a61714425f12e1412da5b7a34f31f7ea5612dd/app/models/project.rb#L619-L636) – weekly project summary is generated | Project student | `receive_feedback_notifications`; a final summary is skipped when a portfolio already exists |
| Task feedback ready | [`Unit#update_task_status_from_csv`](https://github.com/ontrack-features-t2-2026/doubtfire-api/blob/09a61714425f12e1412da5b7a34f31f7ea5612dd/app/models/unit.rb#L2632-L2755) – batch CSV/ZIP marking import finishes feedback/PDF processing | Project student | `receive_feedback_notifications` |
| Weekly staff summary | [`UnitRole#send_weekly_status_email`](https://github.com/ontrack-features-t2-2026/doubtfire-api/blob/09a61714425f12e1412da5b7a34f31f7ea5612dd/app/models/unit_role.rb#L187-L193) – weekly staff summary is generated | Staff member represented by the unit role | `receive_feedback_notifications` |
| Single notification email | [`NotificationService.notify` and `deliver_email`](https://github.com/ontrack-features-t2-2026/doubtfire-api/blob/09a61714425f12e1412da5b7a34f31f7ea5612dd/app/services/notification_service.rb#L24-L68) – an event is created and delivered through the notification service | Notification user | `task`, `feedback`, and `portfolio` map to existing preferences; `extension` and `general` currently have no mapping and are allowed by default |
| Task PDF failed – submission job | [`AcceptSubmissionJob#perform`](https://github.com/ontrack-features-t2-2026/doubtfire-api/blob/09a61714425f12e1412da5b7a34f31f7ea5612dd/app/sidekiq/accept_submission_job.rb#L10-L55) – submitted task PDF conversion fails | Project student | `receive_task_notifications` |
| Submission processing error | [`AcceptSubmissionJob#perform`](https://github.com/ontrack-features-t2-2026/doubtfire-api/blob/09a61714425f12e1412da5b7a34f31f7ea5612dd/app/sidekiq/accept_submission_job.rb#L10-L55) – submission processing raises an exception | Configured administrator/error recipient | Operational path; no user preference; only sent when an error mail is available |
| Archive error | [`ArchiveOldUnitsJob#perform`](https://github.com/ontrack-features-t2-2026/doubtfire-api/blob/09a61714425f12e1412da5b7a34f31f7ea5612dd/app/sidekiq/archive_old_units_job.rb#L6-L24) – old-unit archiving raises an exception | Configured administrator/error recipient | Operational path; no user preference |
| D2L grade transfer result | [`D2lPostGradesJob#perform`](https://github.com/ontrack-features-t2-2026/doubtfire-api/blob/09a61714425f12e1412da5b7a34f31f7ea5612dd/app/sidekiq/d2l_post_grades_job.rb#L9-L37) – D2L grade transfer completes | User who initiated the transfer | Direct workflow result; no notification preference check |
| D2L grade transfer failure | [`D2lPostGradesJob#perform`](https://github.com/ontrack-features-t2-2026/doubtfire-api/blob/09a61714425f12e1412da5b7a34f31f7ea5612dd/app/sidekiq/d2l_post_grades_job.rb#L9-L37) – D2L grade transfer fails | User who initiated the transfer | Direct workflow result; no notification preference check |
| Communication email to student | [`ExecuteCommunicationSetJob#execute_email_student_action`](https://github.com/ontrack-features-t2-2026/doubtfire-api/blob/09a61714425f12e1412da5b7a34f31f7ea5612dd/app/sidekiq/execute_communication_set_job.rb#L116-L159) – an active communication rule matches a student and executes its student-email action | Student matched by the communication rule | No v2 preference check; requires rule match, configured action, recipient email and sender email |
| Communication email to staff | [`ExecuteCommunicationSetJob#execute_email_staff_action`](https://github.com/ontrack-features-t2-2026/doubtfire-api/blob/09a61714425f12e1412da5b7a34f31f7ea5612dd/app/sidekiq/execute_communication_set_job.rb#L163-L198) – a staff-email action executes | Tutors and/or convenors selected by the rule | No v2 preference check; requires configured recipient groups, available recipient addresses and sender email |
| Communication action log | [`ExecuteCommunicationSetJob#send_action_log_to_convenors`](https://github.com/ontrack-features-t2-2026/doubtfire-api/blob/09a61714425f12e1412da5b7a34f31f7ea5612dd/app/sidekiq/execute_communication_set_job.rb#L264-L311) – a communication execution produces its action log | Convenors | Requires `send_log_to_convenors?`, convenor addresses and sender email; no v2 preference check |
| Tutor note | [`NotifyTutorNotesJob#perform`](https://github.com/ontrack-features-t2-2026/doubtfire-api/blob/09a61714425f12e1412da5b7a34f31f7ea5612dd/app/sidekiq/notify_tutor_notes_job.rb#L4-L10) – tutor-note notification job runs | Specific recipient supplied to the job | No preference check in this job path |
| PDF-generation error mail | [`submission:generate_pdfs`](https://github.com/ontrack-features-t2-2026/doubtfire-api/blob/09a61714425f12e1412da5b7a34f31f7ea5612dd/lib/tasks/generate_pdfs.rake#L86-L149) – portfolio/PDF generation raises an exception | Configured administrator/error recipient | Operational path; no user preference |
| Portfolio ready | [`submission:generate_pdfs`](https://github.com/ontrack-features-t2-2026/doubtfire-api/blob/09a61714425f12e1412da5b7a34f31f7ea5612dd/lib/tasks/generate_pdfs.rake#L86-L149) – portfolio generation succeeds | Project student | `receive_portfolio_notifications` |
| Portfolio failed | [`submission:generate_pdfs`](https://github.com/ontrack-features-t2-2026/doubtfire-api/blob/09a61714425f12e1412da5b7a34f31f7ea5612dd/lib/tasks/generate_pdfs.rake#L86-L149) – portfolio generation fails | Project student | `receive_portfolio_notifications` |
| Task PDF failed – maintenance | [`notify_failed_submission`](https://github.com/ontrack-features-t2-2026/doubtfire-api/blob/09a61714425f12e1412da5b7a34f31f7ea5612dd/lib/tasks/maintenance.rake#L42-L68) – maintenance PDF processing identifies a failed submission | Project student | `receive_task_notifications` |
| Maintenance error mail | [`notify_failed_submission`](https://github.com/ontrack-features-t2-2026/doubtfire-api/blob/09a61714425f12e1412da5b7a34f31f7ea5612dd/lib/tasks/maintenance.rake#L42-L68) – maintenance processing raises an error while handling the failure | Configured administrator/error recipient | Operational path; no user preference |
| Overseer assessment failed | [`notify_failed_overseer_assessments!`](https://github.com/ontrack-features-t2-2026/doubtfire-api/blob/09a61714425f12e1412da5b7a34f31f7ea5612dd/lib/tasks/overseer_notifications.rake#L2-L18) – unnotified Overseer assessment failures are grouped for delivery | Affected project student | Requires queued failure records and a nonblank student email; no explicit user preference check in this method |

## Mailers already present

The API currently contains the following relevant mailers:

- `CommunicationsMailer` – sends configurable communication emails and
  communication action logs.
- `D2lResultMailer` – reports D2L grade-transfer results.
- `ErrorLogMailer` – sends operational/error reports.
- `NotificationsMailer` – sends single event notifications and weekly student
  and staff summaries.
- `PortfolioEvidenceMailer` – handles task PDF failure, task feedback ready,
  Overseer assessment failure, portfolio ready and portfolio failed emails.
- `TutorNoteMailer` – sends tutor-note notifications to a supplied recipient.

`ConvenorContactMailer#request_project_membership` and
`PortfolioEvidenceMailer#task_pdf_ready_message` also exist, but no active
`.deliver`/`.deliver_now` send site was found for either during this audit.
They are therefore not counted among the 21 current email send sites.

## Existing web communication subsystem

The web application already contains a unit communications editor under:

`src/app/units/states/edit/directives/unit-communications-editor/`

This is an existing communication system rather than a placeholder for future
notification work.

A convenor can configure communication rules with conditions and actions.
Available actions include:

- Send email to student
- Send email to staff
- Add a task comment
- Change target grade

Student emails support a configurable subject and body. Staff emails also
support configurable subject/body content and can target tutors, convenors, or
both.

Communication rules can filter students using existing conditions including
task status, target grade, login status, special consideration, tutorial,
tutorial stream and campus.

The subsystem also supports scheduled communication sets. A schedule can run
once or recur daily, weekly or monthly. It supports a start week/day/time,
timezone, recurrence interval, repeat count and optional end date.

When a communication set executes, matched students can receive the configured
actions. The execution logic also prevents a student matched by an earlier rule
in the same set from being processed again by a later rule.

## Duplicate-email risks

The existing communications subsystem is the largest duplication risk for v2.
OnTrack can already send configurable email to students and staff, including
scheduled and recurring communication across a unit. A new event should not
reimplement this behaviour without first deciding whether the event belongs in
the existing communication-rule system.

Portfolio events are another clear overlap. OnTrack already emails a student
when portfolio generation succeeds and when it fails. A v2 portfolio event that
also sends email could therefore double-mail the same student.

Task and feedback events must also be checked against
`PortfolioEvidenceMailer`, weekly summaries and the communication-rule system.
Existing task-PDF failures and feedback-ready messages already reach students.

Tutor-note and task-comment work also require care. Tutor notes already have a
direct email path, while the communication editor can create task comments.
New notification hooks around these actions should establish whether the
existing email is being replaced, supplemented, or intentionally left alone.

`NotificationService` introduces another duplication boundary. Events routed
through it can generate a notification email after the relevant notification
preference check. An event must not also retain an independent legacy email
unless two messages are explicitly intended.

The current target branch also includes the `task_status_changed` event. This
event calls `NotificationService.notify`, so it reuses the single notification
email delivery path listed above. It does not introduce a separate direct
`.deliver`, `.deliver_now`, or `.deliver_later` call and therefore does not
increase the direct send-site count.

## Recipient and preference observations

Existing emails do not use one common preference mechanism.

Task-PDF failure paths use `receive_task_notifications`. The batch feedback-ready
email, weekly student summary and weekly staff summary use
`receive_feedback_notifications`. Portfolio-ready and portfolio-failed emails
use `receive_portfolio_notifications`.

`NotificationService` only maps `task`, `feedback`, and `portfolio` to existing
preference fields. The `extension` and `general` types have no preference
mapping, so `NotificationService.deliver_to?` currently allows them by default.

Communication-rule emails do not use the v2 preference mapping. They are
controlled by rule matching, action configuration, available recipient
addresses and an available sender address. The action-log email also requires
the rule's `send_log_to_convenors?` setting and at least one convenor email.

Administrator error emails and D2L result emails have no user notification
preference check. Error emails depend on the operational error-email
configuration, while D2L result emails are sent directly to the user who
initiated the transfer.

This distinction must be preserved when an existing email is migrated or
connected to a v2 event. Adding a second preference check without understanding
the legacy path could suppress a required operational email. Keeping both an
independent legacy send and a v2 send could instead cause duplicate user-facing
email.

## Conclusion

OnTrack already has substantial email functionality in both repositories.

In particular:

1. Students are already emailed when their portfolio is ready or generation
   fails.
2. Students already receive task, feedback, summary and Overseer-related
   emails in existing flows.
3. Staff already receive weekly summaries and can be targeted through the unit
   communications system.
4. Convenors can already configure and schedule email to a unit without any
   new v2 notification feature.
5. The communication subsystem supports both student and staff email and
   recurring schedules.
6. New v2 events must be checked against these send paths before another email
   channel is added.

The safest rule for subsequent event tickets is therefore: before adding an
email delivery path, check this audit and the existing communication subsystem
to determine whether OnTrack already sends an equivalent message.
