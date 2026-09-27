# Event: unit_session_changed

| Field | Value |
|---|---|
| Event name | `unit_session_changed` |
| Category | `unit_hub` |
| What triggers it | A published session that has not finished changes its start, end, time zone, recurrence, location or join link, is cancelled (including through the delete endpoint), or is put back on. `UnitLearningSession` calls `UnitHub::Notifications.session_committed` after an update commits. |
| Who receives it | `UnitHub::Notifications.recipients`, never the author. |
| Preference that gates it | As `unit_announcement_published`. |
| Email subject | `#{product name}: New notification`, the generic subject. |
| Email body summary | A changed session gets the new unit, title, when, where and repeat details. A cancellation gets its own heading, a bold line saying it is cancelled and a status row, and never the join link. Templates `unit_session_changed.html.erb` and `.text.erb`. |
| Where it is raised | `UnitSessionNotificationJob#perform`. |

## Guards

- dedupe key `unit_session_changed:<id>:v<lock_version>`;
- a queued time change for a session cancelled since is dropped, the
  cancellation has its own job;
- creating a session, a description edit, a draft and a past session send
  nothing.

Message copy is `"<title> in <unit> has changed. Now: <when>, <where>."`, or
`"<title> in <unit> on <when> is cancelled."`, or for a weekly session
`"The weekly <title> sessions in <unit> are cancelled."` Push body is the fixed
`A session in your unit has changed.`

## Tests

`test/models/notification_unit_session_test.rb`
