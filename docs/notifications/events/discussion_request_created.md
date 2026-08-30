# Event: discussion_request_created

| Field | Value |
|---|---|
| Event name | `discussion_request_created` |
| Category | `feedback` |
| What triggers it | A tutor raises an audio discussion request for a student's task. `Task#add_discussion_comment` saves the request and every audio attachment before notifying. |
| Who receives it | The student whose task owns the discussion (`discussion.recipient`, set to `project.student`). |
| Preference that gates it | `receive_feedback_notifications` |
| Email subject | `#{product name}: New notification`, using the existing `NotificationsMailer#single_notification` subject |
| Email body summary | Tells the student that a discussion prompt is ready and links back to the task. Audio and prompt content are omitted. Templates are `app/views/notifications_mailer/discussion_request_created.text.erb` and `.html.erb`. |
| Where it is raised | `app/models/task.rb`, in `Task#add_discussion_comment`, after the discussion record and all prompt attachments have been saved |

## Product decision requested for EN-V08

EN-V08 was named "Email when a discussion or check-in is booked". OnTrack has
no booking, appointment, or calendar record for a discussion or check-in, so
there is no truthful booking event to raise.

This implementation proposes the closest existing action with the same user
intent: a tutor creating an audio discussion request through
`Task#add_discussion_comment`. The event is named
`discussion_request_created` to distinguish it from the existing
`DiscussionPrompt` model and its task-definition prompt-management API. The
email says that a prompt is ready and never claims that a meeting was booked.

The Email Notifications lead should confirm this replacement event before the
PR merges. If the replacement is rejected, close the PR without merging it.

`Task#add_discussed_comment` and `Task#add_checked_in_comment` are not hook
points. They record that an interaction already happened, in the past tense.

## Notification fields

- Type: `feedback`
- Event: `discussion_request_created`
- Recipient: `project.student`
- Message: `A discussion prompt is ready for you.`
- Link: `/projects/:project_id/dashboard/:task_abbreviation`
- Preference: `receive_feedback_notifications`

The message deliberately leaves out the tutor's name, task name, unit, audio,
and prompt content. The task route is used so the student can act without
searching for the prompt.

## Delivery timing and failure handling

The notification is raised only after every uploaded prompt has been accepted,
converted, and attached. A rejected or failed attachment therefore does not
produce a premature email. A request with multiple audio prompts still produces
one notification after the final attachment succeeds.

`Task#notify_discussion_request_recipient` rescues notification errors so an
email or notification failure cannot undo an already-created discussion
request. `NotificationService` separately handles email-channel failures.

## Preference behaviour

The proposed replacement is categorised as `feedback`, matching the existing
tutor-to-student `task_comment_created` event. A student who turns off feedback
notifications receives no in-app, email, or push notification for this event.

The original EN-V08 ticket suggested `general`, which would always deliver and
could not be opted out of. That always-on behaviour also required a lead
decision, so the proposal uses the safer existing preference until product
owners decide otherwise.

## How to check it by hand

1. As a tutor, open a student's task and create an audio discussion prompt.
2. Confirm the student receives exactly one notification and one email after
   every prompt upload completes.
3. Confirm the email links to the task but does not contain the audio, prompt
   content, task or unit name, or tutor name.
4. Repeat with feedback notifications turned off and confirm nothing is sent.
5. Confirm marking a task as discussed or checked in does not send this event.

## Tests

`test/models/notification_discussion_request_test.rb`

The tests cover a real valid audio attachment, one notification for multiple
audio prompts, no notification after a failed attachment, recipient, event and
category, feedback preference gating, push link, event-specific email copy,
assessment-content omissions, and failure isolation.
