# Event: unit_session_starting_soon

| Field | Value |
|---|---|
| Event name | `unit_session_starting_soon` |
| Category | `unit_hub` |
| What triggers it | `SendUnitSessionRemindersJob`, every five minutes from `config/schedule.yml`, finds occurrences of published, uncancelled sessions in active units starting within the next 30 minutes. |
| Who receives it | `UnitHub::Notifications.recipients` who also have `receive_unit_hub_session_reminders` on, never the author. |
| Preference that gates it | `receive_unit_hub_session_reminders` (default off) as the opt-in, then the category and channel columns as `unit_announcement_published`. |
| Email subject | `#{product name}: New notification`, the generic subject. |
| Email body summary | Unit, session, when and where for that occurrence, one button to the Unit Hub, and a footer about session reminders. Templates `unit_session_starting_soon.html.erb` and `.text.erb`. |
| Where it is raised | `SendUnitSessionRemindersJob#remind`. |

## Guards

- dedupe key `unit_session_starting_soon:<id>:<occurrence start epoch>`, so the
  six runs that see one occurrence send one reminder, and each weekly
  occurrence gets its own;
- a run after the start sends nothing.

The opt-in covers every session in the user's units. There is no per-session
sign-up to hang it on. Push body is the fixed `A session in your unit starts soon.`

## Tests

`test/models/notification_unit_session_test.rb`
