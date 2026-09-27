# Event: portfolio_submitted

| Field | Value |
|---|---|
| Event name | `portfolio_submitted` |
| Category | `portfolio` |
| What triggers it | A new manual portfolio submission through `PUT /api/projects/:id` with `compile_portfolio: true`, the same moment `portfolio_received` goes to the student. |
| Who receives it | Every tutor of the student's tutorial enrolments. With none, the unit's main convenor. The student and the staff member who made the request are skipped. |
| Preference that gates it | The recipient's `receive_portfolio_notifications`. |
| Email subject | `#{product name}: New notification`, the generic subject. |
| Email body summary | Names the student and unit, with one button to the staff portfolio view (`Notification#web_path`). Templates are `app/views/notifications_mailer/portfolio_submitted.html.erb` and `.text.erb`, on the shared `notification_mail` layout. |
| Where it is raised | `app/api/projects_api.rb`, in the `notify_portfolio_submitted` helper. |

## Guards

- only a new submission notifies, the same test `portfolio_received` uses;
- the dedupe key is the project id plus the submission time, so a retried
  request does not notify twice and a later resubmission does;
- failures are logged and never stop the submission.

The message is `"#{student.name} submitted a portfolio in #{unit.code}."`, the
link is `/projects/<project id>/dashboard` and the notifiable is the project, so
the web client can open the staff portfolio view from `unit_id` and
`project_id`.

## Privacy

The push body is the fixed `A student submitted a portfolio.` so the student's
name does not reach a lock screen.

## Tests

`test/models/notification_portfolio_submitted_test.rb`
