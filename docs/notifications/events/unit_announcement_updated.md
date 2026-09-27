# Event: unit_announcement_updated

| Field | Value |
|---|---|
| Event name | `unit_announcement_updated` |
| Category | `unit_hub` |
| What triggers it | A visible announcement's title or body changes in a way `UnitHub::Notifications.meaningful_edit?` counts. |
| Who receives it | The same recipients as `unit_announcement_published`. |
| Preference that gates it | As `unit_announcement_published`. |
| Email subject | `#{product name}: New notification`, the generic subject. |
| Email body summary | As the published email, with the current title and summary. Templates `unit_announcement_updated.html.erb` and `.text.erb`. |
| Where it is raised | `UnitAnnouncementNotificationJob#notify_updated`. |

## What counts as meaningful

Case, spacing and punctuation never count. Any changed word containing a
digit counts. One word swapped for another within two letters of it, where both
are four letters or more, is a typo, and so is a doubled word taken out. Any
other change to the words counts.

## Guards

- at most one per announcement per recipient in 30 minutes, and a publish in
  that window counts, so an edit straight after posting sends nothing;
- dedupe key `unit_announcement_updated:<id>:<content digest>`;
- one update job per announcement at a time, it reads the announcement as it is
  when it runs.

Push body is the fixed `An announcement in your unit was updated.`

## Tests

`test/models/notification_unit_announcement_test.rb`
