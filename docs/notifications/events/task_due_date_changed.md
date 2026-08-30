# Event: task_due_date_changed

## Purpose

Notify eligible students when a convenor changes a task definition's due date
through the normal task-definition update API.

## Trigger

The trigger is in `app/api/task_definitions_api.rb`.

Immediately after `task_def.update!(task_params)`, the API captures
`saved_change_to_due_date`. After the rest of the update succeeds, it enqueues
`TaskDueDateChangedNotificationJob`.

A `TaskDefinition` model callback is deliberately not used. Task definitions
can also be saved by unit date propagation, imports, rollovers, copies and
internal maintenance. A model callback could therefore create unexpected
cohort-wide email fan-out.

## Queue

The API request does not perform the cohort email and push fan-out directly.
`TaskDueDateChangedNotificationJob` performs the fan-out through Sidekiq.

A functioning Sidekiq worker must consume the same
`DF_REDIS_SIDEKIQ_URL` used by the API.

## Recipient eligibility

A project is eligible only when:

- the unit is active;
- the project is enrolled;
- the project's target grade is at least the task definition's target grade;
  and
- the student has task notifications enabled.

Recipients are selected from projects rather than existing Task rows. OnTrack
creates Task rows on demand, so an eligible student may not yet have one. The
notification job does not create Task rows.

## Stale jobs and duplicate queue entries

The job receives:

- the task definition ID;
- the previous stored due date; and
- the new stored due date.

Before sending, it checks that the task definition still has the queued new raw
due date. This prevents an outdated job from sending after the due date has
changed again.

Sidekiq uniqueness rejects another pending or executing job with the same task
definition ID and old/new date values.

Automatic retries are disabled because retrying a partly completed cohort
fan-out could create duplicate notifications for students already processed.
A failure for one project is logged without stopping the remaining projects.

## Notification fields

- Type: `task`
- Event: `task_due_date_changed`
- Message: names the task and unit but does not expose the due date
- Link: `/projects/:project_id/dashboard/:task_abbreviation`
- Preference: `receive_task_notifications`

## Bulk unit date changes

Changing a unit start date updates many task definitions internally. This
implementation does not send one email per changed task for that path.

A future unit-level notification or digest should cover bulk schedule changes
without sending many separate emails to each student.

## Templates

- `app/views/notifications_mailer/task_due_date_changed.text.erb`
- `app/views/notifications_mailer/task_due_date_changed.html.erb`

## Tests

- `test/sidekiq/task_due_date_changed_notification_job_test.rb`
- `test/api/units/task_definitions_api_test.rb`

The tests cover:

- eligible students without Task rows;
- target-grade filtering;
- withdrawn students;
- notification preferences;
- inactive units;
- stale jobs;
- privacy-safe message content and links;
- the event-specific email template;
- enqueue on a due-date API update;
- no enqueue for unrelated updates;
- no enqueue from direct model updates; and
- queue failure not breaking the core due-date update.