# Event: task_status_changed

A staff member changes the status of a task. The student is told. Ticket EN-E02.

Built the same way as the worked example in `task_comment_created.md`; read that
one first.

## What it does

A tutor marks a task, and the student whose task it is gets an email telling them
the status changed.

- A tutor changes the status, the student is emailed.
- A student changing their own task is not emailed about their own action.

## Where it is raised

`app/models/task.rb`, in `notify_student_of_status_change`, called at the end of
`trigger_transition` once the transition has succeeded and the new status has
been saved.

    NotificationService.notify(
      user: project.student,
      type: 'task',
      event: 'task_status_changed',
      message: "#{by_user.name} updated the status of #{task_definition.abbreviation} in #{unit.code}.",
      link: "/projects/#{project.id}/dashboard/#{task_definition.abbreviation}"
    )

## Fields

| Field | Value |
|---|---|
| `type` | `task`, so the student's `receive_task_notifications` switch controls it |
| `event` | `task_status_changed` |
| `message` | Who acted, which task, which unit. Never the new status value |
| `link` | `/projects/<project id>/dashboard/<task abbreviation>` |

## Templates

- `app/views/notifications_mailer/task_status_changed.text.erb`
- `app/views/notifications_mailer/task_status_changed.html.erb`

`NotificationsMailer#single_notification` picks the template named after the
event when it exists. Adding this event never required editing the mailer.

## Three things to know before you copy this

1. **Only a staff action notifies.** The guard is `role == :tutor`. A student
   changing their own task (submitting, working on it) must never email
   themselves. `role` is already worked out at the top of `trigger_transition`.

2. **Only a real change notifies.** The status before the transition is captured
   and compared at the end. Re-applying the same status is a no-op and sends
   nothing.

3. **A notification must never break the transition.** The call is wrapped in a
   `rescue StandardError` that logs and swallows. Marking a task must succeed
   even if notifying fails.

## How to check it by hand

1. Sign in as a tutor, open a student's task, change its status.
2. An email to the student arrives at http://localhost:8025 (Mailpit). It names
   the tutor and the task, and does not contain the new status value.
3. Sign in as that student, change one of their own tasks, and confirm no email
   is sent to themselves.
4. Turn that student's task notifications off in their profile, have the tutor
   mark again, and no email arrives.

## Known limitations and deliberate choices

- **Bulk marking queues one email and one push job per task.** `Project#trigger_week_end`
  (`app/models/project.rb`) loops `trigger_transition(trigger: 'complete',
  bulk: true)` over a student's discuss/demonstrate tasks, and this event ignores
  the `bulk:` flag, so a single request can enqueue several near-identical
  notifications. Provider delivery occurs in Sidekiq, but the queue hand-offs
  still happen in that request. The path is latent today — no
  `doubtfire-web` caller drives `trigger_week_end`. Left un-suppressed on purpose
  so bulk-marked tasks still notify; batching many into one email belongs with the
  event design, not here.

- **The fix-and-resubmit cascade does not raise this event.** Inside `assess`, the
  `recursive_fix` cascade calls `assess` directly on dependent tasks instead of
  going through `trigger_transition`, so those status changes raise nothing here.
  The student is still emailed, but via `task_comment_created` (the cascade adds an
  automated comment) — i.e. under a different event. Reconciling that is out of
  scope for EN-E02.

- **Site admins acting on the student-side branches notify nobody.** `user_role`
  returns `:admin` for an unenrolled site admin, who can still drive the
  `working_on_it` / `need_help` / `not_started` / `ready_for_feedback` branches.
  The `role == :tutor` guard means those changes notify no one. That is intended:
  an admin poking at a task is not a tutor marking it for the student.

## Tests

`test/models/notification_task_status_test.rb`

Covers the staff change, the student's own action sending nothing, an unchanged
status sending nothing, the preference switch, the status value staying out of
the email, the event-specific template being used, a bulk mark still notifying,
and that a notification failure still leaves the transition committed.

Not yet covered: the group-task fan-out (each member emailed about their own
task). The behaviour is correct — `propagate_transition` threads `by_user`
through a per-member `trigger_transition` — but a factory-built group task test
is a worthwhile follow-up.
