# Event: task_submitted

| Field | Value |
|---|---|
| Event name | `task_submitted` |
| Category | `task` |
| What triggers it | A student submits a task and it genuinely moves into the ready-for-feedback (ready-for-marking) state through `Task#trigger_transition`. |
| Who receives it | `project.tutor_for(task_definition)`, the tutor responsible for that task. A missing tutor is guarded and raises no notification. |
| Preference that gates it | The recipient tutor's `receive_task_notifications` preference. |
| Email subject | `#{product name}: New notification`, built by `NotificationsMailer#single_notification`. The generic subject deliberately does not identify the student or task. |
| Email body summary | Names the student and task so the assigned tutor knows what is waiting. The submission and all assessment content are deliberately omitted. Templates are `app/views/notifications_mailer/task_submitted.text.erb` and `.html.erb`. |
| Where it is raised | `app/models/task.rb`, in `Task#notify_tutor_of_task_submission`, called at the end of `Task#trigger_transition` after a successful status change. |

## Transition and duplicate guards

`task_submitted` shares the successful-transition seam used by EN-E02's
`task_status_changed`, but the two events have disjoint actor guards:

- `task_submitted` only runs for a student or group member moving a task into
  `TaskStatus.ready_for_feedback`;
- `task_status_changed` only runs for a tutor changing a student's task.

The previous and current status IDs are compared, so submitting again while the
task is already ready for feedback does not send another email.

Group submissions can invoke the transition once per member task and then
visit those tasks again through submission propagation. Calls marked
`group_transition: true` are suppressed, leaving the original action as the
single notification boundary.

## Privacy

The email names the student and task because the recipient is the assigned
tutor and needs both to identify the waiting work. It does not contain uploaded
work, marks, grades, feedback, comments, or any other assessment content. The
link opens the authenticated task page in OnTrack.

## Volume

Independent submissions still produce one immediate email each. A tutor with
many students may therefore receive many messages in a short period. A digest
would require queueing and aggregation work beyond this event; this
implementation prevents duplicate amplification but does not batch unrelated
submissions.

## How to check it by hand

1. Sign in as a student and submit a task for marking.
2. Confirm exactly one email arrives for the tutor returned by
   `project.tutor_for(task_definition)`.
3. Confirm the email names the student and task, links to the task, and contains
   no submission or assessment content.
4. Repeat with the tutor's task notifications disabled and confirm no
   notification is created or delivered.

## Tests

`test/models/notification_task_submitted_test.rb`

The focused tests cover the recipient and preference, exact event/category,
ready-for-marking status guard, EN-E02 separation, duplicate and group
propagation guards, HTML/text copy, task link, nil tutor, push payload shape,
and failure isolation.
