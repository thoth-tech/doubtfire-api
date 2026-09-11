# Cross-Project Dashboard Feedback State

## Purpose

The Cross-Project Dashboard needs to distinguish genuine staff feedback from the existing general unread comment count without exposing feedback content.

## Response contract

When task data is included in the authenticated student's `/api/projects` response, each task may include:

| Field | Type | Meaning |
| --- | --- | --- |
| `has_feedback` | Boolean | Whether the task has qualifying manual staff feedback according to the existing `Task#has_manual_feedback_since_first_ready_for_feedback?` rule. |

Example:

```json
{
  "id": 123,
  "task_definition_id": 45,
  "status": "complete",
  "num_new_comments": 1,
  "has_feedback": true
}
```

## Exact meaning

`has_feedback` is `true` when the existing task feedback rule finds at least one qualifying comment:

- the comment type is `text`, `audio`, `image`, `pdf`, or `discussion`;
- the comment was authored by unit teaching staff;
- when the task has entered Ready for Feedback, the comment was created on or after the first Ready for Feedback event;
- the comment is not an automated message beginning with `**Automated Message:**`.

The field reuses the existing backend feedback definition rather than introducing a dashboard-specific definition.

## Privacy and access control

Only the boolean feedback state is exposed.

The dashboard response does not expose:

- feedback text;
- marker notes;
- feedback author details;
- feedback timestamps;
- unread-feedback state;
- another student's feedback state.

`GET /api/projects` derives projects from the authenticated `current_user`. Direct project access continues to use the existing project authorisation checks.

## Compatibility

Frontend consumers must treat `has_feedback` as optional. Missing feedback metadata must not prevent the Cross-Project Dashboard from loading and is treated as no available feedback state.

## Scope

This ticket does not add feedback text, feedback timestamps, author information, or unread-feedback tracking. Any future expansion requires a separate privacy and contract review.
