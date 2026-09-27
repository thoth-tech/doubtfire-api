# Event: extension_requested

| Field | Value |
|---|---|
| Event name | `extension_requested` |
| Category | `task` |
| What triggers it | A student asks for an extension. `Task#apply_for_extension` saves the `ExtensionComment`, runs any automatic approval, then calls `notify_extension_request_recipient`. |
| Who receives it | `extension.recipient`, set by `apply_for_extension` and read rather than worked out again. That is `Task#tutor`, which is `Project#tutor_for` and so the unit's main convenor when the student has no tutor. When more weeks are asked for than are left before the due date (`Task#weeks_can_extend`) it is the main convenor directly, though the request endpoint caps the weeks at that number so only a direct model call reaches that branch. A blank recipient is guarded. |
| Preference that gates it | The recipient's `receive_task_notifications`, shown to staff as "Task notifications" in their profile. Turned off, nothing is created, emailed or pushed. |
| Email subject | `#{product name}: New notification`, built by `NotificationsMailer#single_notification`, the same generic subject as every other event. |
| Email body summary | Names the student and task and asks the reader to open the task to grant or reject the request. The reason the student gave is left out. It ends with the same link to manage notification preferences as `task_submitted`. Templates are `app/views/notifications_mailer/extension_requested.text.erb` and `.html.erb`. |
| Where it is raised | `app/models/task.rb`, in `Task#notify_extension_request_recipient`, called at the end of `Task#apply_for_extension`, which `POST /projects/:project_id/task_def_id/:task_definition_id/request_extension` calls. |

## Guards

Only a request still waiting on a person notifies.

- The requester must be the project's student. Staff creating an extension are
  assessed on the spot and never notify, even when that assessment fails.
- A request the unit approves automatically is assessed before the notification
  is considered, so it does not notify. The student hears the outcome through
  `extension_assessed`.
- The check is `extension.assessed?`, not the automatic approval setting. An
  automatic approval that cannot be applied leaves the request waiting, and
  that one does notify.
- The recipient is never the person who asked.

The message is `"#{user.name} asked for an extension on #{task_definition.name} in #{product_name}."`
and the link is `/projects/<project id>/dashboard/<task abbreviation>`, the same
shape `task_submitted` uses. The notification targets the extension comment, so
opening the task's comments clears it from the bell. The comment itself stays
unread for the recipient until someone assesses it, as it did before.

## Why it is a task notification

`extension` has no entry in `Notification::PREFERENCE_FOR_TYPE`, so an
`extension` notification is always sent and a tutor could not switch it off.
As `task` it sits under "Task notifications" with `task_submitted` and
`task_help_requested`, the other things a student asks a tutor to act on. The
event name still says what happened. The student-facing `extension_assessed`
keeps the `extension` category.

The web app has no presentation entry for this event yet, so it falls back to
the category and shows the generic task icon and "Task" label rather than the
extension icon. Adding `extension_requested` to `EVENT_PRESENTATIONS` in
`notification-presentation.ts` would change that.

## Privacy

The in-app message and email name the student and task, and leave out the
reason the student gave. The push body is the fixed
`A student asked for an extension.` from
`PushNotificationService::LOCK_SCREEN_BODY_OVERRIDES`. That copy follows the
MN-S04 rule but has not been added to the MN-S04 sign-off in
`docs/notifications/reviews/`.

## Tests

`test/models/notification_extension_request_test.rb`
