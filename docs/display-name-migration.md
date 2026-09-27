# Display Name Migration

## Canonical rule

Normal user-facing display names use:

- preferred/nickname first name + surname when a preferred name exists
- legal first name + surname when no preferred name exists

The API is the source of truth for this rule.

Both parts are trimmed. A missing, empty or whitespace-only nickname falls back
to the trimmed legal first name. Empty parts are omitted and the remaining parts
are joined with one space. Preserve spelling and Unicode; do not title-case,
truncate or append the legal first name to the display value. A display name is
not unique: use the user ID for associations and actions, and an existing
authorised identifier when a staff member needs to distinguish namesakes.

Use `User#display_name` for a user instance or `User.display_name_for` when working with name attributes outside a full user instance.

API entities expose this value as:

`display_name`

The Web application maps this to:

`displayName`

## Contributor guidance

New user-facing UI should use `displayName` rather than reconstructing a name from `firstName`, `lastName`, `nickname`, `preferredName`, or the legacy `name` property.

Do not add new frontend fallback logic for normal display names.

`User#name` and the Web `User.name` property remain legacy behaviour and were not globally changed in MISC-PN02 to avoid an unrelated broad refactor.

## Priority surfaces migrated in MISC-PN02

The scoped migration covers priority user-facing areas including:

- task comments and comment-related views
- task and staff views
- dashboards and progress views
- student and staff lists
- student-list CSV export
- search display matching
- selected notification/confirmation text

## Known lower-priority surfaces not migrated

The following areas still contain legacy name construction and should use the shared display-name value when they are migrated in future work:

- group management and group alerts
- portfolio/review screens
- SCORM learner-name integration
- similarity/footer display
- QR/header display
- tutorial and campus alerts
- legacy `User.name`
- comment initials generation

These are deferred migration surfaces, not approved legal-name exceptions.

## Legal-name exceptions and access

This is the proposed shared contract for MISC-PN01 review. The normal display
rule above is already implemented. Repository review does not establish an
institution's legal or administrative requirement; the institution's privacy
and administration owners must approve any exception before it is introduced.

| Purpose | Name to display | Access and exception rule |
| --- | --- | --- |
| Student/staff screens, feedback authors, dashboards, notifications and ordinary class lists | `display_name` / `displayName` | Existing endpoint and unit membership authorisation still applies. Do not add a second legal-name label. |
| A person editing their own identity/profile | Distinct, explicitly labelled editable fields | Only the person and existing authorised administrators. A profile field is not a reason to expose both names elsewhere. |
| An identity check, statutory record or an approved official export | Legal first name and surname only when the receiving process requires them | Record the purpose, responsible institutional owner, allowed roles, receiving system and retention requirements in the change's review. Do not infer permission merely because a user is staff. |
| Ordinary CSV/class-list export | Display name | The current student-list export uses the shared helper. Retaining separate legal-name columns in an administrative import/export requires the documented exception above. |

No new legal-name exception is approved by this document. Existing portfolio,
SCORM and other legacy name construction below must be reviewed on its actual
purpose; its current implementation is not evidence of an approved exception.

## Search and privacy

Normal result labels use the canonical display name. Search may match preferred
name, legal first name, surname and an authorised identifier only within the
records and fields the caller is already allowed to access. A match must not
reveal the hidden matching legal name in a tooltip, highlighted snippet or
secondary label. Search must never expand a student request into a global user
directory. The current Web `User.matches` searches already-loaded user records;
it is not an access-control boundary.

Do not attach both names to push payloads, email subjects, public links or logs
to disambiguate people. Keep full feedback text and names out of dashboard
metadata. Namesakes must not be merged or treated as the same account.

## Source audit and next migration boundaries

Reviewed against API `bb360dfa` and Web `d16f6201c` (`11.0.x`). This is a code
audit, not a claim of institutional approval or a live-user test.

| Surface | Current source and behaviour | Follow-up priority |
| --- | --- | --- |
| Shared API and Web model | `app/models/user.rb` exposes `display_name_for`/`display_name`; `app/api/entities/user_entity.rb` exposes it; Web `src/app/api/models/user/user.ts` stores `displayName` | Use this contract for new code; retain the existing helper tests. |
| Feedback author display | Web `src/app/tasks/task-comments-viewer/task-comments-viewer.component.html` uses `comment.author.displayName`; extension comments use it too | The same template still uses `comment.recipient.name` in a recipient label. Migrate that label before claiming the whole surface is complete. |
| Dashboard | Cross-project cards display unit/task names, not another student's name; other user-bearing views were migrated in MISC-PN02 | Keep dashboard feedback metadata free of additional identity fields. |
| Search | Web `User.matches` matches `displayName`, legal first name, surname, nickname and existing identifiers | Preserve authorised search while showing only the canonical result label. |
| Notifications | `app/views/notifications_mailer/*` still has `@user.name` and `@user.first_name`; communication templates use nickname/first-name greetings | Prioritise normal notification name migration. These are ordinary correspondence, not legal-name exceptions. Keep HTML and text alternatives consistent. |
| Reports and exports | Student-list export uses the canonical helper; `app/views/portfolio/portfolio_pdf.pdf.erb` and `app/views/task/task_pdf.pdf.erb` still render legal name fields | Ask the record owner which outputs require legal names; migrate ordinary output and document approved official exceptions individually. |
| Legacy Web helper | `User.name` truncates each name and appends nickname | Do not use it in new normal display surfaces; migrate consumers by feature to avoid changing administrative output silently. |

Reviewers should confirm the normal rule, search visibility and exception
process together. Any approval and institutional exceptions belong in the PR
review or a linked institutional decision; do not fill in assumed approvals.
