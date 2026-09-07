# Notification events

Every notification event gets its own file in this folder. One event, one file,
named after the event.

    docs/notifications/events/task_comment_created.md
    docs/notifications/events/task_status_changed.md
    docs/notifications/events/extension_granted.md

The file name is the string passed as `event:` to `NotificationService.notify`.
If the code says `event: 'task_comment_created'` then the file is
`task_comment_created.md`. No other naming, no grouping by category, no folders
inside this one.

## Why one file each

Eight event tickets run at the same time. If they all documented their event in
one shared file, every one of them would edit the same lines and every one would
conflict with the other seven. The first to merge wins and the other seven stop
to fix a merge by hand, for a docs change that had nothing to do with anyone
else's work.

Adding a file conflicts with nothing. Two people can add
`task_status_changed.md` and `extension_granted.md` on the same afternoon and
neither branch touches the other.

This is the same reason the mailer looks its template up by event name instead
of holding a lookup table. A new event adds
`app/views/notifications_mailer/<event>.html.erb` and `.text.erb` and edits no
existing file. The docs follow the code.

## Adding one

1. Copy `_template.md` to `<your_event_name>.md`.
2. Fill in the eight fields. Read the code and copy the real values out of it,
   do not write down what you think it does.
3. Delete the field guidance and the worked example from your copy. Both are
   there to be read once. Carrying them into every event file is the duplication
   this folder exists to avoid.

The underscore on `_template.md` keeps it at the top of the listing and marks it
as not being an event. The worked example inside it is an example and not the
record for that event, so one event one file still holds. Nothing reads this
folder in code, so the underscore is only for people.

## What this folder is not

It is not the design of the notification system. That is `NOTIFICATIONS.md` at
the repo root, and it covers the service, the types, the preferences and the
channels. A file in here is the record of one event: what sets it off, who hears
about it, and where to find the line that raises it. Keep the general
explanation out of it, there is one copy of that already.
