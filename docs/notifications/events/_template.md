# Event: <event_name>

| Field | Value |
|---|---|
| Event name | |
| Category | |
| What triggers it | |
| Who receives it | |
| Preference that gates it | |
| Email subject | |
| Email body summary | |
| Where it is raised | |

## What goes in each field

**Event name.** The exact string passed as `event:` to
`NotificationService.notify`. Lower case with underscores. It is also the file
name of this document and the name of the mailer templates, so get it right
once and it lines up everywhere.

**Category.** The `type:` argument. One of `task`, `feedback`, `portfolio`,
`extension`, `general`, from `Notification::TYPES` in
`app/models/notification.rb`. The category is what the user's preference
switches on, so pick the one that matches how a user would think about turning
this off.

**What triggers it.** The thing a person did, in a sentence. Then the method
that runs afterwards. "A tutor saves a text comment" is more use to the next
reader than "the comment callback fires".

**Who receives it.** The `user:` argument, and how it is worked out. Say plainly
if it can be nil and what happens then. Most of the bugs in this area are a
recipient that was assumed to exist.

**Preference that gates it.** The user column in
`Notification::PREFERENCE_FOR_TYPE` that the category maps to, spelled out in
full. Write `none, always sent` for `extension` and `general`, which have no
entry there. When the preference is off the notification is dropped on every
channel, the in-app bell included.

**Email subject.** What lands in the inbox. Every notification shares one
subject built in `NotificationsMailer#single_notification`, so unless you
changed the mailer this is the same line as everyone else's. The product name
at the front is config and not a fixed word, so quote the line that builds it
and say what your stack sets it to.

**Email body summary.** Two or three lines on what the email tells the reader,
and what it leaves out on purpose. Name the templates. If the event has no
templates of its own say so, the mailer falls back to the generic
`single_notification` pair and the email is much plainer.

**Where it is raised.** `path/to/file.rb:<line>`, the method it sits in, and
what calls that method. Line numbers move, so name the method too, that is the
part a reader can still find in six months.

Anything else worth knowing goes below the table under its own headings.
Recipient guards, things left out on purpose, how to check it by hand, the test
file. Keep it short.

---

# Worked example

This is `task_comment_created`, the first event wired into OnTrack, from ticket
EN-E01. The code it describes lives on `email/task-comment` until that branch
merges, so read the paths below there. Copying the template gives you a copy of
this section and of the guidance above it. Delete both from your own file.

| Field | Value |
|---|---|
| Event name | `task_comment_created` |
| Category | `feedback` |
| What triggers it | Someone saves a text comment on a task. `Task#add_text_comment` saves the comment and then calls `notify_comment_recipient` |
| Who receives it | `comment.recipient`, set by `add_text_comment` at `task.rb:945` and read here rather than worked out again. The student when a tutor commented. When a student commented it is `Project#tutor_for`, which gives the tutorial's tutor, or the unit's main convenor when there is no tutorial or the tutorial has no tutor |
| Preference that gates it | `receive_feedback_notifications` |
| Email subject | `#{product name}: New notification`, built at `app/mailers/notifications_mailer.rb:22`. `config/institution.yml` defaults the product name to `Doubtfire` and `DF_INSTITUTION_PRODUCT_NAME` overrides it. Our deploy sets `OnTrack`, so the inbox shows `OnTrack: New notification` |
| Email body summary | Greets the user by name, gives one line saying who commented on which task in which unit, then says the comment is not included and to open the task to read it. A link to the task and a line about turning the emails off. Templates are `app/views/notifications_mailer/task_comment_created.text.erb` and `.html.erb` |
| Where it is raised | `app/models/task.rb:971`, in `Task#notify_comment_recipient`, called from `add_text_comment` at line 949 |

## Notes

The comment text never goes into the message or the email. The email is a prompt
to come back to OnTrack, not a copy of the conversation. The message is built as
`"#{comment.user.name} commented on #{task_definition.abbreviation} in #{unit.code}."`
and the link is `/projects/<project id>/dashboard/<task abbreviation>`.

Raising a notification must not stop a comment being posted, so
`notify_comment_recipient` rescues `StandardError`, logs it and carries on. That
is a second layer. `NotificationService.deliver_email` already rescues mail
failures on its own.

`notify_comment_recipient` returns early on a blank recipient. The comment in
the code says that happens when the project has no tutor, which is not right,
`Project#tutor_for` falls back to the main convenor. The guard is cheap
insurance rather than a case anyone has hit, and the test for it passes a nil
recipient in by hand instead of going through `add_text_comment`.

The subject is generic on purpose. Per-event subjects need a lookup that every
event ticket would have to edit, which is the collision this folder exists to
avoid. It is a known limitation, left as it is for now.

## How to check it by hand

1. Sign in as a tutor, open a student's task and post a comment.
2. Development mail is written to a file, and `development/docker-compose.yml`
   mounts `../data/tmp` over `/doubtfire/tmp`, so it lands on the host under
   `doubtfire-deploy/data/tmp/mails/`. The file is named after the recipient's
   address and every email to that address is appended to the same one. Open the
   student's file and read the last message. It names the commenter and the task
   and does not contain the comment text.
3. Turn that student's feedback notifications off in their profile and comment
   again. Nothing is appended. Do not go looking for a new file, there is only
   ever the one per address.

## Tests

`test/models/notification_task_comment_test.rb`. Both directions, the preference
switch, the missing recipient, the comment text staying out of the email, and a
notification failure still leaving the comment saved.
