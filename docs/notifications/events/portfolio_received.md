# Event: portfolio_received

| Field | Value |
|---|---|
| Event name | `portfolio_received` |
| Category | `portfolio` |
| What triggers it | A student successfully starts a new manual portfolio submission through `PUT /projects/:id` with `compile_portfolio: true`. A repeated request while the same manual submission is already pending is not a new submission. |
| Who receives it | The submitting student (`project.student`). |
| Preference that gates it | `receive_portfolio_notifications` |
| Email subject | `#{product name}: New notification`, using the existing `NotificationsMailer#single_notification` subject |
| Email body summary | Confirms the date and time that the portfolio submission was received, including its timezone and UTC offset, and links to the project's current status. It says explicitly that the receipt does not confirm an assessment outcome. No portfolio contents, marks, grades, feedback, or other student information are included. Templates are `app/views/notifications_mailer/portfolio_received.text.erb` and `portfolio_received.html.erb`. |
| Where it is raised | `app/api/projects_api.rb`, in the `PUT /projects/:id` `compile_portfolio` branch, after the new submission state and `portfolio_submission_date` have been saved. |

## Existing portfolio emails are different events

The existing email audit records `PortfolioEvidenceMailer#portfolio_ready` and
`PortfolioEvidenceMailer#portfolio_failed`. Those messages are raised later by
`submission:generate_pdfs` after portfolio generation succeeds or fails.

`portfolio_received` is the earlier receipt for accepting the student's
submission. It uses the shared `NotificationService` email path and does not
call either legacy portfolio mailer. One accepted submission therefore sends
one receipt, while a later generation result remains a separate event.

## New-submission guard

A receipt is raised only when a new manual submission is accepted:

- `compile_portfolio` changes from false to true; or
- a pending auto-generated portfolio is replaced by the student's manual
  submission.

Retrying `compile_portfolio: true` while the same manual submission is already
pending does not create another notification and does not replace the original
`portfolio_submission_date`. Setting `compile_portfolio: false` does not send a
receipt. Once generation has finished and the flag is false again, a later
manual resubmission is new and receives its own receipt.

The decision and save happen while holding a row lock on the project, so two
concurrent retries cannot both observe the submission as new.

## Receipt time

The saved `project.portfolio_submission_date` is the source of truth. It is
rendered in the project's campus timezone. When the project has no campus
timezone, the application timezone is used. The email includes the local date,
time, timezone abbreviation and numeric UTC offset, for example:

`23 August 2026 at 10:34 PM AEST (UTC+10:00)`

This is receipt metadata only. The notification and email never include the
portfolio, an assessment result, marks, grades, feedback or rationale.

## Implementation

The event uses:

- `type: 'portfolio'`
- `event: 'portfolio_received'`
- recipient: `project.student`
- `link: "/projects/#{project.id}/dashboard"`

`NotificationService` applies `receive_portfolio_notifications` before it
creates the in-app notification or delivers email and push. A failure while
raising the notification is logged without rejecting the already accepted
portfolio submission.

## How to check it by hand

1. Sign in as a student and submit a portfolio.
2. Confirm that exactly one receipt appears in Mailpit and that it is addressed
   to the submitting student.
3. Confirm that the receipt contains the saved date, time, timezone and UTC
   offset, and contains no portfolio or assessment content.
4. Repeat the same request while generation is pending and confirm that no
   second receipt appears.
5. Turn off portfolio notifications, submit again after generation has
   completed, and confirm that no notification or email is created.

## Tests

`test/models/notification_portfolio_test.rb`

The focused tests cover the recipient, event/type, generic subject, push link,
event-specific copy, timestamp and privacy boundary, portfolio preference,
duplicate-request guard, later resubmission, manual replacement of an
auto-generated portfolio, cancellation, and notification failure isolation.
