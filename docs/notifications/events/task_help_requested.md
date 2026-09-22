# Event: task_help_requested

| Field | Value |
|---|---|
| Event name | `task_help_requested` |
| Category | `task` |
| What triggers it | A student moves their task to Need Help through `Task#trigger_transition`, and the status actually changes. That is either the status menu, or uploading work with `trigger: 'need_help'`, which `Task#create_submission_and_trigger_state_change` turns into the same transition. |
| Who receives it | `project.tutor_for(task_definition)`, the task's tutor, or the unit's main convenor when the student has no tutor for that task. A blank recipient is guarded and raises nothing. |
| Preference that gates it | The recipient's `receive_task_notifications`, shown to staff as "Task notifications" in their profile. |
| Email subject | `#{product name}: New notification`, built by `NotificationsMailer#single_notification`, the same generic subject as every other event. |
| Email body summary | Names the student and task so the tutor knows who is stuck, with a link to the task. The student's work and comments are left out. Templates are `app/views/notifications_mailer/task_help_requested.text.erb` and `.html.erb`. |
| Where it is raised | `app/models/task.rb`, in `Task#notify_tutor_of_student_request`, called at the end of `Task#trigger_transition`. The same method raises `task_submitted`. |

## Guards

It shares every guard with `task_submitted`, because it is the same method:

- only a student or group member moving the task notifies, so a tutor setting
  Need Help raises `task_status_changed` for the student and nothing for the
  tutor;
- an unchanged status does not notify again;
- calls marked `group_transition: true` are suppressed. Changing the status
  of a group task does not spread Need Help to the other members, but
  uploading group work with the Need Help trigger does, once per member task.
  Only the uploader's own task notifies, so the tutor hears about it once;
- the tutor is never notified about their own action.

The message is `"#{student.name} asked for help with #{task_definition.name} in #{product_name}."`
and the link is `/projects/<project id>/dashboard/<task abbreviation>`, the same
shape `task_submitted` uses. The notification targets the task, so opening the
task's comments clears it from the tutor's bell.

## Privacy

The in-app message and email name the student and task. The push body is the
fixed `A student asked for help with a task.` from
`PushNotificationService::LOCK_SCREEN_BODY_OVERRIDES`, so neither reaches a lock
screen. That copy follows the MN-S04 rule but has not been added to the MN-S04
sign-off in `docs/notifications/reviews/`.

## Tests

`test/models/notification_task_help_requested_test.rb`
