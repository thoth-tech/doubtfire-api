# Unit hub: announcements, HelpHubs and classes

The unit hub puts staff-published announcements and scheduled learning sessions in one place. Content belongs to the actual OnTrack unit offering ID, not just a unit code. A student enrolled in SIT111 cannot read SIT102 content by changing a browser filter or an API ID.

## Delivered behaviour

- A signed-in feed combines announcements and the next 90 days of sessions from active units in which the user is currently enrolled or assigned as teaching staff.
- Assigned tutors and convenors can create, edit, publish and remove announcements, and create, edit and cancel sessions. Observer-only staff can read published content, but cannot manage it. A global staff or admin account does not automatically gain unrelated unit hub access.
- Draft, future-published and expired announcements do not appear in the student feed. Unpublished sessions do not appear. Feed data and subscription responses use `Cache-Control: private, no-store`.
- HelpHub, lecture, seminar, workshop and other session types support a safe HTTPS join link and optional location/source link. Content is plain text; the client must not interpret it as HTML. The server does not fetch staff links.
- A weekly schedule repeats on the original weekday at the original local time. Staff can create separate Thursday and Friday schedules. Recurrence must end within six months and produces at most 27 occurrences. There is no unbounded rule parser.
- Existing calendar subscriptions can explicitly opt in to learning sessions. This also shares their session titles, location and join links with the chosen calendar provider. Existing unit exclusions apply. Announcements and announcement bodies are never included.

## API contract

All routes below are relative to `/api` and require the existing OnTrack authentication header, except the existing token-protected public calendar URL.

| Route | Result |
| --- | --- |
| `GET /unit_hub` | `{units, announcements, sessions, announcements_truncated, window_start, window_end}` |
| `GET /units/:unit_id/announcements` | Assigned non-observer teaching staff only; all announcement rows, including drafts and expired rows |
| `POST /units/:unit_id/announcements` | Create `{announcement: {...}}`; returns the saved row |
| `PUT /units/:unit_id/announcements/:id` | Update allowed fields through `{announcement: {...}}`; returns the saved row |
| `DELETE /units/:unit_id/announcements/:id` | Remove an announcement |
| `GET /units/:unit_id/sessions` | Assigned non-observer teaching staff only; raw schedules, including drafts/cancelled rows |
| `POST /units/:unit_id/sessions` | Create `{session: {...}}`; returns the saved raw schedule |
| `PUT /units/:unit_id/sessions/:id` | Update through `{session: {...}}`; returns the saved raw schedule |
| `DELETE /units/:unit_id/sessions/:id` | Cancel the schedule, retaining identity for calendar cancellation notices |
| `GET /webcal` | Existing preferences plus `include_learning_sessions` when enabled |
| `PUT /webcal` | Existing wrapper, e.g. `{webcal: {enabled: true, include_learning_sessions: true}}` |

Unit rows contain `id`, `code`, `name` and `can_manage`. Announcement rows additionally expose `source_provider`, `managed_externally`, `author_name` and `source_imported_at`; private source keys and credentials are never returned. Unit rows also expose `teams_sync` as `configured` or `not_configured` (configuration status, not proof of a live connection). Announcement rows contain `id`, `unit_id`, `unit_code`, `unit_name`, `title`, `body`, `source_url`, `pinned`, `published_at`, `expires_at` and `updated_at`. Set `published_at` to null to save a draft. Up to 100 announcements appear, pinned first then newest; the truncation flag makes this bound explicit.

Session rows contain `id`, `unit_id`, `unit_code`, `unit_name`, `title`, `description`, `kind`, `start_at`, `end_at`, `timezone`, `location`, `join_url`, `source_url`, `published`, `cancelled`, `recurrence`, `recurrence_until` and `updated_at`. `kind` is one of `helphub`, `lecture`, `seminar`, `workshop`, `other`. `recurrence` is `none` or `weekly`. New schedules default to unpublished. The feed expands schedules into occurrences and additionally includes `occurrence_id` and `original_start_at`. Staff listing and write responses return the original schedule. Feed cancellation rows have `join_url: null`.

Date-time inputs must use ISO 8601 and include an explicit UTC offset, for example `2026-10-08T17:00:00+11:00`. `timezone` is an IANA identifier such as `Australia/Melbourne`; `recurrence_until` is `YYYY-MM-DD`. Session end must be after start and within 24 hours. Announcement bodies and session descriptions are limited to 20,000 characters; titles to 200. Links must be HTTPS without whitespace or embedded credentials. Invalid model data produces HTTP 400 with a readable `error`; unauthorized unit IDs or records produce 404 and enrolled users without management rights receive 403.

## Calendar behaviour and privacy

Learning sessions default to off, including for existing subscriptions. Once enabled, the subscription checks current enrolled projects, active current units and unit exclusions on every request. Sessions are queried independently from task definitions, so units without tasks still work. Withdrawing from a unit removes its sessions from the next fetched calendar. Users can revoke or rotate the existing subscription token in the existing preferences flow.

Each occurrence has a stable UID based on schedule ID and week index. Rescheduling updates the same UID; Rails' increasing `lock_version` becomes the iCalendar sequence, so rapid edits remain ordered. Deleting a schedule marks it cancelled and retains a `STATUS:CANCELLED` event without a join link. Cancellation records remain in the rolling 30-day past/six-month future subscription window. Calendar providers choose when they refresh, so changes and revocations are not instant and previously downloaded copies cannot be erased by OnTrack. Manually added Google Calendar events and downloaded ICS files are snapshots; use a subscription for ongoing updates.

Weekly expansion adds local calendar weeks before UTC export to preserve ordinary HelpHub times across daylight saving. A recurrence landing in a missing clock-change hour follows the time-zone library's forward normalization; use daytime session times or review that occurrence if such a schedule is needed. This release does not support per-occurrence exceptions or automatic timetable import.

## Deployment and demo boundary

Run the migrations through `20260914000002` before starting the matching web release. They add `unit_announcements`, `unit_learning_sessions`, the calendar preference and the calendar revision field. Existing data is retained, and existing calendar subscriptions keep their prior content until the user opts in.

The normal feature uses real authenticated API records. The web application's existing explicit demo mode uses synthetic client-side examples and makes no hub write requests. These migrations and normal seeds contain no screenshot material or invented real class links. The Teams screenshots were examples of student needs, not commands, credentials or authorized access to Teams. Staff can enter approved source and meeting links. The optional [university-managed Teams announcement sync](teams-sync.md) imports only configured student-wide channels and approved staff publishers; it defaults to off and requires university application consent. Existing SSO is unchanged, and students do not sign in again. Imported rows are managed in Teams, preserve source ownership, and remain subject to OnTrack enrolment checks.

## Verification

Focused tests cover cross-unit isolation, withdrawn enrolments, inactive units, drafts, expiry, future publication, staff/observer permissions, forged IDs, link/date validation, authentication, weekly DST behavior, bounded recurrence, opt-in subscriptions, unit exclusions, units without tasks, final-day inclusion, stable UID updates and cancellation without stale join links.

Configure the `DF_TEST_DB_*` settings to a dedicated, seeded test database before running these commands. Never point them at a development database holding work:

```sh
RAILS_ENV=test bundle exec rake db:migrate
RAILS_ENV=test bundle exec ruby -Itest -r./config/environment -e 'ActiveRecord.maintain_test_schema = false; ARGV.each { |path| require File.expand_path(path) }' test/api/unit_hub_api_test.rb test/models/unit_learning_session_test.rb test/models/unit_hub_calendar_test.rb
```

Existing calendar API/model tests should run alongside these before release. The runtime evidence and exact counts are recorded with the delivery, rather than assumed here.
