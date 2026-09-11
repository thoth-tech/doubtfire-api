
# Safe Starter Email Templates

## Purpose

These starter templates provide privacy-aware wording for OnTrack email
notifications. They avoid exposing unnecessary assessment information in email
subject lines and bodies.

Recipients should sign in to OnTrack to view task names, unit information,
feedback, marks, comments, submissions, dates, and other assessment details.

## Privacy Guidelines

- Keep subject lines generic.
- Do not include student names in subject lines.
- Do not include unit names or task names in subject lines.
- Do not include marks, grades, feedback text, tutor comments, or submission details.
- Direct users to sign in to OnTrack to view protected information.
- Do not include personal information or authentication tokens in URLs.
- Respect the user's notification preferences.
- Use configured OnTrack names and URLs instead of hard-coded deployment details.

## Suggested Placeholders

- `{{product_name}}`: the configured system name, such as OnTrack.
- `{{sign_in_url}}`: a secure link to the OnTrack sign-in page.
- `{{notification_settings_url}}`: the user's notification settings page.

---

## 1. Due Soon

### Subject

```text
{{product_name}} reminder: a due date is approaching
```

### Body

```text
Hello,

A task in {{product_name}} is due soon.

Sign in to review the task and confirm the due date:
{{sign_in_url}}

No assessment details are included in this email.

You can manage your notification preferences here:
{{notification_settings_url}}
```

### Privacy Note

This email does not include the task name, unit name, due date, submission
status, or other assessment details.

---

## 2. Feedback Available

### Subject

```text
{{product_name}} notification: feedback is available
```

### Body

```text
Hello,

New feedback is available in {{product_name}}.

Sign in to view it securely:
{{sign_in_url}}

No feedback content is included in this email.

You can manage your notification preferences here:
{{notification_settings_url}}
```

### Privacy Note

This email does not include feedback text, task names, unit names, staff
comments, marks, or assessment results.

---

## 3. Task Marked

### Subject

```text
{{product_name}} notification: a task has been marked
```

### Body

```text
Hello,

A task has been marked in {{product_name}}.

Sign in to review the outcome and any next steps:
{{sign_in_url}}

No mark or result is included in this email.

You can manage your notification preferences here:
{{notification_settings_url}}
```

### Privacy Note

This email does not include the mark, grade, result, task name, unit name,
or feedback.

---

## 4. Date Changed

### Subject

```text
{{product_name}} notification: a task date has changed
```

### Body

```text
Hello,

A date associated with a task has changed in {{product_name}}.

Sign in to confirm the current date:
{{sign_in_url}}

Use the date displayed in {{product_name}} as the current source of truth.

You can manage your notification preferences here:
{{notification_settings_url}}
```

### Privacy Note

This email does not include the task name, unit name, previous date, or new date.

---

## Key Finding

The API repository already contains notification mailer functionality and
notification-related email views. Future implementation should investigate
reusing the existing mailer structure instead of creating a separate email
delivery system.

## Recommended Next Step

Before production implementation, the Email Notifications team should confirm:

1. The trigger for each notification.
2. The user roles that receive each notification.
3. The secure destination URL for each email.
4. Whether exact dates may be included in email bodies.
5. Whether emails are sent immediately or through a background job.
6. How notification preferences and opt-out behaviour are applied.

Production mailer code, event triggers, database changes, and frontend notification settings are outside the scope of this starter documentation task.