# Event: group_membership_changed

| Field | Value |
|---|---|
| Event name | `group_membership_changed` |
| Category | `general` |
| What triggers it | A student's direct group membership changes through `Group#add_member` or `Group#remove_member`. Internal tutorial-switch operations and bulk CSV imports are intentionally suppressed. |
| Who receives it | Only the student whose membership changed (`project.student`). Other members of the group are not notified. This recipient scope was confirmed with the Email Notifications lead. |
| Preference that gates it | none, always sent |
| Email subject | `#{product name}: New notification`, using the existing `NotificationsMailer#single_notification` subject |
| Email body summary | Tells the affected student that they were added to or removed from a group. The membership change is not broadcast to other group members. Templates are `app/views/notifications_mailer/group_membership_changed.text.erb` and `group_membership_changed.html.erb` |
| Where it is raised | `app/models/group.rb:154` in `Group#add_member` and `app/models/group.rb:175` in `Group#remove_member`. Both call the private `notify_group_membership_change` helper at line 187 |

## Recipient scope

The agreed scope is **student only**.

Only the student who was added to or removed from the group receives the notification. Other group members are not notified because a removal should not be broadcast to the group, and notifying the whole group would multiply the number of sends for a single membership change.

## Tutorial switch guard

`Group#switch_to_tutorial` temporarily removes and re-adds members while moving the group to another tutorial. These internal membership operations do not represent a real group membership change and must not send a leave-then-join notification pair.

## Bulk CSV import guard

`Unit#import_student_groups_from_csv` may add many students in one request. It calls `Group#add_member(..., notify: false)` so the import does not create and deliver one notification for every CSV row.

If bulk-import notifications are required later, they should be queued or batched after a successful import rather than delivered separately inside the import request.

## Implementation

The event uses:

- `type: 'general'`
- `event: 'group_membership_changed'`
- recipient: `project.student`
- `link: "/projects/#{project.id}/groups"`

Event-specific HTML and text email templates are provided under `app/views/notifications_mailer/`.

## How to check it by hand

1. Use a unit with Group Work enabled and an existing student project.
2. Add the student to a group.
3. Open Mailpit at `http://localhost:8025` and confirm that one email is sent to the affected student.
4. Remove the same student from the group and confirm that one removal email is sent.
5. Confirm that no other group members receive the notification.
6. Move the group to another tutorial and confirm that the temporary remove/add operations do not create a leave-then-join email pair.

## Tests

`test/models/notification_group_test.rb`

The tests cover:

- adding a member sends one notification to the affected student
- removing a member sends one notification to the affected student
- other group members are not notified
- `switch_to_tutorial` does not send a leave-then-join notification pair
- a notification failure does not stop the membership change
- bulk CSV imports add students without raising per-student notifications
- the push payload points to the affected project's group page
