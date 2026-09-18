# Event: tutorial_changed

| Field | Value |
|---|---|
| Event name | `tutorial_changed` |
| Category | `general` |
| What triggers it | An existing tutorial enrolment is moved in place by `Project#enrol_in`. A first enrolment, selecting the same tutorial again, and the multiple-enrolment collapse path do not trigger it. |
| Who receives it | Only the affected project's student (`project.student`). Students in the old or new tutorial are not notified. |
| Preference that gates it | none, always sent |
| Email subject | `#{product name}: New notification`, using the existing `NotificationsMailer#single_notification` subject |
| Email body summary | Names the new tutorial and gives its meeting day and time. It deliberately omits the old tutorial and any other student's details. Templates are `app/views/notifications_mailer/tutorial_changed.text.erb` and `tutorial_changed.html.erb`. |
| Where it is raised | `app/models/project.rb`, in the existing-enrolment update branch of `Project#enrol_in`, through the private `notify_tutorial_changed` helper |

## Recipient and trigger guards

The notification is addressed directly to `project.student`. It is not fanned
out through either tutorial's enrolments, so one student's move creates one
notification and one email.

`Project#enrol_in` has distinct paths for creating a first enrolment, collapsing
multiple stream enrolments into a single non-stream enrolment, and updating an
existing enrolment. Only the final path calls `notify_tutorial_changed`, after
the tutorial enrolment update succeeds. Selecting the current tutorial returns
before any of those paths and does not notify.

## Notification fields

- Type: `general`
- Event: `tutorial_changed`
- Recipient: `project.student`
- Message: names the new tutorial abbreviation, unit, meeting day and meeting time
- Link: `/projects/:project_id/dashboard`
- Preference: none; `general` has no entry in `Notification::PREFERENCE_FOR_TYPE`

The previous tutorial is intentionally absent from the notification record,
email and push body. Marks, feedback, comments and other student names are not
included.

Notification errors are logged and do not roll back a successful tutorial move.

## How to check it by hand

1. As a convenor, move one student from an existing tutorial to another.
2. Confirm that exactly one email is sent to that student.
3. Confirm that the email names the new tutorial and its day and time, and does
   not name the old tutorial or any other student.
4. Add a student to their first tutorial and confirm that no email is sent.

## Tests

`test/models/notification_tutorial_test.rb`

The tests cover the affected-student recipient, notification fields and push
link, both email formats, privacy-safe copy, first enrolment, the same-tutorial
no-op, the multiple-enrolment collapse path, and notification failure isolation.
