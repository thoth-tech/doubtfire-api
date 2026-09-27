# New Task Available Notification

## Event

`new_task_available`

## Purpose

Notifies eligible students when a newly created task becomes available.

## Trigger

The notification fan-out is queued after a task definition is successfully
created through any supported workflow:

- the normal task-definition API;
- CSV task import; or
- task copying during unit rollover.

These workflows enqueue only after the task definition is fully populated. A
general `TaskDefinition` `after_create` callback is intentionally not used
because CSV import and rollover save intermediate records before their full
workflow is complete.

`SendNewTaskAvailableNotificationsJob` also checks active units once a day.
It sends on or shortly after the student's effective start date, covering task,
target-grade and student-specific future dates without creating missing `Task`
rows. A seven-day catch-up window tolerates short worker outages and late
enrolment without announcing historical tasks.

A tracking timestamp marks definitions that are ready for this sweep. New
application code leaves the marker empty until an explicit workflow completes;
the database supplies a UTC marker only for writes from an older process during
a rolling deployment. The sweep gives those compatibility rows an hour to
settle before evaluating them.

## Notification

- Type: `task`
- Event: `new_task_available`
- Recipient: eligible students enrolled in the unit
- Preference: `receive_task_notifications`

`NotificationService` applies the existing task-notification preference before creating and delivering the notification.

## Recipient eligibility

A student receives the notification only when all of the following are true:

- The task was created through a supported direct, copy/rollover or import workflow.
- The unit is active.
- The student is currently enrolled in the unit.
- The task applies to the student's target grade.
- The student's effective task start date is now or earlier for an immediate
  creation fan-out, or within the scheduled release check's bounded window.
- The student has task notifications enabled.

The student's effective start date is determined with
`Webcal.start_date_for_task_definition`, the same calculation used by the
student calendar. Flexible dates, target-grade dates and supported
student-specific date adjustments are therefore respected.

## Fan-out

Notification delivery is not performed directly inside the API request.

After a task-definition creation workflow completes, it enqueues:

`NewTaskAvailableNotificationJob`

The job processes enrolled projects in batches and sends one notification to
each eligible student whose task is already available. The scheduled release
job processes future start dates in daily batches.

Duplicate notifications for the same student and task are prevented by an
immutable task-definition key backed by a unique database index. Renaming a
task does not resend it, while a genuinely new definition that reuses an old
abbreviation can still notify. Delivery is serialized on the notification row,
outside the student's project lock, so normal retries do not duplicate a
completed delivery. External email and push remain at-least-once: a process
failure after a provider accepts a message but before completion is recorded
can repeat that external message on retry.

## Email templates

HTML:

`app/views/notifications_mailer/new_task_available.html.erb`

Plain text:

`app/views/notifications_mailer/new_task_available.text.erb`

## Link

The notification links the student to the new task on their project dashboard:

`/projects/:project_id/dashboard/:task_abbreviation`

## Future and bulk-created tasks

Future-dated tasks are not announced early. The scheduled release job notifies
each student on or shortly after their effective start date. Unit rollover and
CSV import enqueue only after their multi-step workflow completes, so a worker
cannot observe a partially populated task definition. Updated CSV rows do not
generate a new-task notification.

All paths use the same event, preference gate and duplicate guard. A bulk import
may deliberately enqueue one cohort fan-out per newly created task, but none of
that email delivery happens in the API request.

## Tests

Automated tests are located at:

`test/models/notification_new_task_test.rb`

The tests cover:

- notification for an eligible student
- fan-out to multiple eligible students
- task-notification preference disabled
- unenrolled students
- task target-grade eligibility
- inactive units
- future base, target-grade and student-specific start dates
- rollover/copy and new CSV-import rows
- no notification for updated CSV rows
- no `Task` rows created by the scheduled sweep
- immutable database deduplication and retry state
- rolling-deployment tracking compatibility

Test command:

`bundle exec rails test test/models/notification_new_task_test.rb`

The focused tests are also in:

`test/sidekiq/send_new_task_available_notifications_job_test.rb`
