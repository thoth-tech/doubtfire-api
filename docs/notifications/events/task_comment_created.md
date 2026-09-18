# Event: task_comment_created

The first notification event wired into OnTrack. Ticket EN-E01.

This is the worked example. If you are adding an event, copy the shape of this
one.

## What it does

Someone posts a text comment on a task. The other party is told.

- A tutor comments, the student is emailed.
- A student comments, the tutor is emailed.

## Where it is raised

`app/models/task.rb`, in `notify_comment_recipient`, called at the end of
`add_text_comment` once the comment has saved.

    NotificationService.notify(
      user: comment.recipient,
      type: 'feedback',
      event: 'task_comment_created',
      message: "#{comment.user.name} commented on #{task_definition.abbreviation} in #{unit.code}.",
      link: "/projects/#{project.id}/dashboard/#{task_definition.abbreviation}"
    )

## Fields

| Field | Value |
|---|---|
| `type` | `feedback`, so the recipient's `receive_feedback_notifications` switch controls it |
| `event` | `task_comment_created` |
| `message` | Who commented, which task, which unit. Never the comment text |
| `link` | `/projects/<project id>/dashboard/<task abbreviation>` |

## Templates

- `app/views/notifications_mailer/task_comment_created.text.erb`
- `app/views/notifications_mailer/task_comment_created.html.erb`

`NotificationsMailer#single_notification` picks the template named after the
event when it exists, and falls back to `single_notification.*.erb` when it does
not. That is why adding an event never requires editing the mailer.

## Three things to know before you copy this

1. **Do not work out who to notify.** `comment.recipient` is already set by
   `add_text_comment`: the tutor when a student commented, the student when a
   tutor commented.

2. **Guard for no recipient.** A project with no tutor for the task definition
   has no recipient. `notify_comment_recipient` returns early. Without that it
   raises.

3. **A notification must never break the thing that triggered it.** The call is
   wrapped in a `rescue StandardError` that logs and swallows. Posting a comment
   must succeed even if notifying fails.

## How to check it by hand

1. Sign in as a tutor, open a student's task, post a comment.
2. A file appears in `doubtfire-deploy/data/tmp/mails/`, addressed to the
   student. It names the commenter and the task, and does not contain the
   comment text.
3. Turn that student's feedback notifications off in their profile, comment
   again, and no new file appears.

## Tests

`test/models/notification_task_comment_test.rb`

Covers both directions, the preference switch, the absent recipient, the comment
text staying out of the email, and that a notification failure still leaves the
comment saved.

## Known limitation

The email subject is the generic "New notification". Per-event subjects would
need a shared lookup in the mailer, which would make every event ticket edit the
same file and collide. Left as it is on purpose.
