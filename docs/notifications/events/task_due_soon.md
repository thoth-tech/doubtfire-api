# Event: task_due_soon

## Purpose

Remind a student that a task they still owe is nearly due, so a deadline is not
the first they hear about it.

## Trigger

Nothing a person does. Every other event in this folder hangs off an action:
a comment is posted, a due date is edited, a status changes. A deadline getting
closer is nobody doing anything, so there is no model to hook and no callback to
add. The reminder has to be swept for.

`SendDueSoonRemindersJob` does the sweep. `config/schedule.yml` runs it under the
name `send_due_soon_reminders`.

## Schedule

`every day at 8am`.

Once a day, because a deadline only moves once a day and every notification this
job raises sends an email. Sweeping every thirty minutes would find the same
answer forty-eight times.

At a fixed time, because that also fixes when the emails land. On a short
interval a student gets theirs at whatever hour their task happened to cross
into the window, which is 3am as often as any other hour. Pinning it to the
morning makes the reminder arrive on a day somebody can act on it.

Missing a run costs nothing. The job asks whether a task is due within the next
three days, not whether it crossed a line since the last run, so tomorrow's run
still catches everything a skipped run would have.

**Which 8am depends on the environment.** There is no timezone in the cron
expression, no `config.time_zone` in the app, and sidekiq-cron reads the process
clock, so the hour comes from `TZ`. `development/api.env` sets
`TZ=Australia/Melbourne`, which is what makes this a morning. A deployment that
leaves `TZ` unset gets the image default of UTC and sends these in the evening
local time. `aggregate_task_completion_stats`, at 11:55pm, already depends on the
same thing.

**This has not been seen to fire.** There is no Sidekiq worker in the dev stack,
which is EN-F03, so the schedule entry is unverified beyond the assertion in
`test/sidekiq/scheduled_job_test.rb` that it loads and enqueues.

## Window

Three days, `SendDueSoonRemindersJob::WINDOW_DAYS`.

Long enough to still do something about it over a weekend, short enough that the
reminder is about this task and not about the rest of the trimester.
`Project#top_tasks` calls seven days "soon" for its own purposes, and seven days
of warning on a weekly task is most of the tasks a student has, which is a list
rather than a reminder.

## Recipient eligibility

A project gets a reminder about a task definition only when:

- the unit is active;
- the project is enrolled;
- the project has a target grade set;
- the task definition is assigned at that target grade;
- the task's status is one of `not_started`, `working_on_it`, `need_help`,
  `fix_and_resubmit` or `redo`; and
- the student has task notifications enabled, which `NotificationService`
  enforces rather than this job.

Recipients come from projects and not from Task rows. OnTrack creates a Task row
the first time anyone touches the task, so the students who have not started
have no row, and they are the ones a reminder is for.

**Nothing in this job may call `Project#task_for_task_definition`**, which
creates the row it cannot find, and nothing may call
`Project#task_definitions_and_status` either, because that calls it. The job
reads `project.tasks` once per project and looks each definition up in a hash.

That is also why it is affordable. `task_definitions_and_status` asks for the
assigned definitions per project and then runs two more queries per definition,
so a five hundred student unit with twenty task definitions is upwards of twenty
thousand queries. Here the definitions are read once per unit and the tasks once
per project.

### Statuses deliberately left out

`discuss` and `demonstrate` both mean the student has submitted and is waiting on
a tutor. Telling them the task is due soon is wrong, and it is the kind of wrong
that teaches people to stop reading notifications, so `OUTSTANDING_STATUSES`
lists only the five that mean work is still owed. A project with no Task row at
all counts as outstanding.

## Which deadline

Per student, not per task definition, and answered by
`Webcal.end_date_for_task_definition(task_definition, task, project)`.

That method already exists, already handles both cases, and is what the
student's calendar feed shows them, so writing the rule again here would mean
two answers to "when is this due" that could disagree.

- With a Task row, `Task#local_due_date`, which knows about extensions and about
  a unit's flexible dates.
- Without one, the grade level override when the unit has flexible dates, and
  the task definition's own `target_date` otherwise.

The second case is the one that is easy to get wrong. On a unit with flexible
dates the grade override applies before any Task row exists, so a grade 2
student can be due days away from the unit's own date without ever having opened
the task. `Project#top_tasks` reads `target_date` directly and has this gap;
`Webcal` does not, which is why this follows `Webcal`.

## Duplicates

One reminder per student per task, ever. Before notifying, the job asks:

```ruby
Notification.exists?(user_id:, notification_type: 'task', event: 'task_due_soon', link:)
```

The index `index_notifications_on_user_id_and_event` is what makes that cheap
enough to ask once per candidate task. Without the guard the job runs again
tomorrow, the task is still due soon tomorrow, and the same student is emailed
every morning until the deadline passes.

Known consequence: a task whose deadline is later extended past the window and
then comes back into it does not produce a second reminder. That is deliberate.
The student asked for the extension, so they know about the task, and
`task_due_date_changed` covers a convenor moving it.

## Notification fields

- Type: `task`
- Event: `task_due_soon`
- Message: `"<abbreviation> in <unit code> is due soon."`
- Link: `/projects/:project_id/dashboard/:task_abbreviation`
- Preference: `receive_task_notifications`

The date stays out of the message, the same as `task_due_date_changed`. The row
outlives the deadline it describes, so "due on the 14th" is wrong a week later
while "due soon" only stops being interesting.

## Failure handling

A failure on one project is logged, its id is collected, and the sweep carries on
through the rest of the cohort. At the end of `perform` the collected ids are
raised, which is what `NewTaskAvailableNotificationJob` does and for the same
reason: logging and returning normally would leave `perform` successful, Sidekiq
would schedule no retry, and a student whose task is due today is filtered out as
overdue tomorrow, so that reminder is gone for good.

`retry: 1`. Re-running the whole sweep is only safe because of the duplicate
guard, which skips everyone already reminded.

Sidekiq uniqueness rejects a second copy of the sweep,
`lock: :until_executed` on a fixed lock argument.

## Templates

- `app/views/notifications_mailer/task_due_soon.text.erb`
- `app/views/notifications_mailer/task_due_soon.html.erb`

## Tests

`test/sidekiq/send_due_soon_reminders_job_test.rb`, seventeen cases, covering
eligible students without Task rows, both edges of the window, an already passed
deadline, the duplicate guard, withdrawn students, inactive units, the
notification preference, target grade filtering, a student's own extended
deadline, a flexible unit's grade level deadline with no Task row, a task
waiting on a tutor, a failure being raised rather than swallowed, privacy-safe
content, and the event template.

`test/sidekiq/scheduled_job_test.rb` covers the schedule entry loading and
enqueuing. It counts the entries in `config/schedule.yml`, so adding this one
changed the expected count from six to seven.
