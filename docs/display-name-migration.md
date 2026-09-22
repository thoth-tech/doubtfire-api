# Display Name Migration

## Canonical rule

Normal user-facing display names use:

- preferred/nickname first name + surname when a preferred name exists
- legal first name + surname when no preferred name exists

The API is the source of truth for this rule.

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
