# V2 Event Email Templates (EN-V05 to EN-V08)

## Purpose

These templates provide reader-focused email copy for the remaining four v2
notification events. They follow the privacy rules in
`safe_starter_email_templates.md`: include only the detail needed to explain
what happened, keep assessment content out of email, and direct the recipient
back to OnTrack for the full context.

The subjects below are the preferred product copy. The notification mailer
currently uses the shared subject `{{product_name}}: New notification` for
every event; adopting event-specific subjects requires a separate mailer
decision.

## Shared placeholders

- `{{product_name}}`: the configured product name, such as OnTrack.
- `{{recipient_first_name}}`: the recipient's first name.
- `{{student_name}}`: the student whose task is waiting for marking. Used only
  in the tutor-facing EN-V06 email.
- `{{task_name}}`: the task that is waiting for marking. Used only in EN-V06.
- `{{group_name}}`: the group the student joined or left.
- `{{unit_code}}`: the unit code.
- `{{submitted_at}}`: the portfolio receipt date and time in the project's
  campus timezone, falling back to the application timezone. Include both the
  timezone abbreviation and numeric UTC offset, for example
  `AEST (UTC+10:00)`.
- `{{destination_url}}`: an authenticated OnTrack page for the event.
- `{{notification_settings_url}}`: the recipient's notification settings.

Never substitute marks, grades, feedback, comment text, or portfolio contents
into these placeholders. EN-V06 is the one narrow third-party exception: the
assigned tutor may see the submitting student's name and task name. Do not name
any other student or third party.

---

## EN-V05: Group membership changed

Two versions are required because joining and leaving are different messages.
Only the affected student receives either version.

### Added to a group

#### Subject

```text
{{product_name}} notification: you joined a group
```

#### Plain text body

```text
Hi {{recipient_first_name}},

You have been added to {{group_name}} in {{unit_code}}.

Open {{product_name}} to view your current group:
{{destination_url}}

No other group members are named in this email.

This service notification is always sent.
```

#### HTML body

```html
<p>Hi {{recipient_first_name}},</p>

<p>You have been added to {{group_name}} in {{unit_code}}.</p>

<p><a href="{{destination_url}}">View your current group in {{product_name}}</a></p>

<p>No other group members are named in this email.</p>

<p>This service notification is always sent.</p>
```

### Removed from a group

#### Subject

```text
{{product_name}} notification: your group changed
```

#### Plain text body

```text
Hi {{recipient_first_name}},

You are no longer a member of {{group_name}} in {{unit_code}}.

Open {{product_name}} to view your current group information:
{{destination_url}}

If you did not expect this change, contact your teaching team.

This service notification is always sent.
```

#### HTML body

```html
<p>Hi {{recipient_first_name}},</p>

<p>You are no longer a member of {{group_name}} in {{unit_code}}.</p>

<p><a href="{{destination_url}}">View your current group information in {{product_name}}</a></p>

<p>If you did not expect this change, contact your teaching team.</p>

<p>This service notification is always sent.</p>
```

### Privacy note

Neither version names another student or describes why the membership changed.
The removal copy states the current fact without implying fault or punishment.
The event uses the `general` category, which has no preference gate.

### Implementation alignment

EN-V05 merged before this copy document. Its current templates render the
notification message's "added to" or "removed from" wording and do not yet
include the destination link, softer removal sentence, or always-sent footer
above. Merging this document does not silently change that event; EN-V05 needs a
focused template-and-test follow-up to adopt the approved copy exactly.

---

## EN-V06: Task submitted for marking

This is the only tutor-facing email in this document. Naming the student and
task is necessary so the tutor can identify the work waiting for them. Do not
include the submission, a mark, feedback, or a comment.

### Subject

```text
{{product_name}} notification: a task is ready for marking
```

### Plain text body

```text
Hi {{recipient_first_name}},

{{student_name}} submitted {{task_name}} for marking in {{product_name}}.

Open the task to review the submission:
{{destination_url}}

The submission and any assessment content are not included in this email.

You can manage your notification preferences here:
{{notification_settings_url}}
```

### HTML body

```html
<p>Hi {{recipient_first_name}},</p>

<p>{{student_name}} submitted {{task_name}} for marking in {{product_name}}.</p>

<p><a href="{{destination_url}}">Open the task in {{product_name}}</a></p>

<p>The submission and any assessment content are not included in this email.</p>

<p>
  You can manage your notification preferences in
  <a href="{{notification_settings_url}}">your profile</a>.
</p>
```

### Privacy note

The student name and task name are visible only to the assigned tutor. The
subject remains generic and does not identify the student or task.

---

## EN-V07: Portfolio submission received

This is a receipt for the student who submitted the portfolio. The receipt time
must include an unambiguous timezone. It confirms receipt only; it does not say
that the portfolio is valid, complete, generated, or assessed.

### Subject

```text
{{product_name}} receipt: portfolio submission received
```

### Plain text body

```text
Hi {{recipient_first_name}},

{{product_name}} received your portfolio submission at {{submitted_at}}.

Open {{product_name}} to view its current status:
{{destination_url}}

This receipt confirms when the submission was received. It does not confirm an assessment outcome.

You can manage your notification preferences here:
{{notification_settings_url}}
```

### HTML body

```html
<p>Hi {{recipient_first_name}},</p>

<p>{{product_name}} received your portfolio submission at {{submitted_at}}.</p>

<p><a href="{{destination_url}}">View the current status in {{product_name}}</a></p>

<p>
  This receipt confirms when the submission was received. It does not confirm
  an assessment outcome.
</p>

<p>
  You can manage your notification preferences in
  <a href="{{notification_settings_url}}">your profile</a>.
</p>
```

### Privacy note

The email contains the receipt date and time in the project campus timezone
(application timezone fallback), with both an abbreviation and numeric UTC
offset. It contains no portfolio content, marks, feedback, or other student
information.

---

## EN-V08: Discussion or check-in

### Scope decision required

OnTrack does not currently have a booking or appointment record that can raise
the event as originally named. `Task#add_discussion_comment` does create an
audio discussion request for a student, so `discussion_request_created` is the
proposed replacement. The copy below is for that replacement and must not be
described as a booking confirmation. The Email Notifications lead must approve
the replacement before its implementation merges.

If a real booking model is introduced later, write separate copy that includes
the booked date, time, timezone, and location or meeting method from that model.

### Subject

```text
{{product_name}} notification: a discussion prompt is ready
```

### Plain text body

```text
Hi {{recipient_first_name}},

A discussion prompt is ready for you in {{product_name}}.

Open the task to listen and respond:
{{destination_url}}

The prompt is not included in this email.

You can manage your notification preferences here:
{{notification_settings_url}}
```

### HTML body

```html
<p>Hi {{recipient_first_name}},</p>

<p>A discussion prompt is ready for you in {{product_name}}.</p>

<p><a href="{{destination_url}}">Open the task in {{product_name}}</a></p>

<p>The prompt is not included in this email.</p>

<p>
  You can manage your notification preferences in
  <a href="{{notification_settings_url}}">your profile</a>.
</p>
```

### Privacy note

The email does not include audio, prompt content, comments, task or unit names,
or another person's name. The proposed replacement uses the `feedback`
category and respects `receive_feedback_notifications`.

---

## Review checklist

- Each event has a subject, plain text body, and HTML body.
- EN-V05 covers both joining and leaving a group.
- EN-V06 is written to a tutor and identifies only the student and task needed
  to act.
- EN-V07 includes a date, time, timezone abbreviation, and numeric UTC offset
  and does not overstate what the receipt proves.
- EN-V08 is not presented as buildable booking functionality.
- No template includes marks, grades, feedback, comment text, portfolio
  contents, or unnecessary third-party names.
