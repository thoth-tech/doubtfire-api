# Event: unit_announcement_published

| Field | Value |
|---|---|
| Event name | `unit_announcement_published` |
| Category | `unit_hub` |
| What triggers it | An announcement becomes visible to its unit: created with a publication time that has arrived, a draft given one, an expired one given a later expiry, or a visible one pinned. A future publication time waits for a job scheduled at that time. `UnitAnnouncement` calls `UnitHub::Notifications.announcement_committed` after commit. |
| Who receives it | `UnitHub::Notifications.recipients`: users with an enrolled project in the unit and the unit's tutors and convenors, the unit active, never the author. |
| Preference that gates it | `receive_unit_hub_notifications` for the whole category, then `receive_unit_hub_email_notifications` and `receive_unit_hub_push_notifications` for those channels. Defaults on, off, off. |
| Email subject | `#{product name}: New notification`, the generic subject. |
| Email body summary | Heading, unit, title and a 280 character summary in the details block, one button to the Unit Hub, preferences footer. Templates `unit_announcement_published.html.erb` and `.text.erb`. |
| Where it is raised | `UnitAnnouncementNotificationJob#notify_published`. |

## Guards

- dedupe key `unit_announcement_published:<id>:published-<epoch>`, or
  `pinned-<epoch>` for a pin, per recipient, so a retry or a second job sends
  nothing twice;
- a job for a publication time that has since moved is ignored;
- an announcement created with a publication time over a day before it was
  created is a backfill and is not announced;
- unpinning is not announced.

Link `/unit-hub?unit=<unit id>&announcement=<id>`. Push body is the fixed
`There is a new announcement in your unit.`

## Tests

`test/models/notification_unit_announcement_test.rb`
