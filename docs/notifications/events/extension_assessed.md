# Event: extension_assessed

| Field | Value |
| --- | --- |
| Event name | `extension_assessed` |
| Category | `extension` |
| What triggers it | A tutor or the automatic extension flow assesses an extension request through `ExtensionComment#assess_extension`. |
| Who receives it | `project.student`. The notification is only raised after the assessment is successfully saved. |
| Preference that gates it | `none, always sent` |
| Email subject | `#{product name}: New notification`, built by `NotificationsMailer#single_notification`. |
| Email body summary | Tells the student whether the extension was granted or rejected. A granted notification includes the updated due date. The event uses `extension_assessed.html.erb` and `extension_assessed.text.erb`. |
| Where it is raised | `app/models/comments/extension_comment.rb`, in `ExtensionComment#assess_extension`, after `save!`. |

## Failure behaviour

No notification or email is sent when:

- the extension request was already assessed;
- the deadline prevents an extension from being granted; or
- `Task#grant_extension` does not successfully apply the extension.

A failed `grant_extension` call also leaves the extension request unassessed so that the system does not record or communicate a false successful result.

## Tests

`test/models/notification_extension_test.rb`

The tests cover:

- granted extensions and the updated due date;
- rejected extensions;
- already-assessed requests;
- deadline failures;
- a failed `grant_extension` operation;
- HTML and text event-specific templates.