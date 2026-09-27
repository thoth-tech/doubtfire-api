# Course Flow planning API

Course Flow supports private, saved study plans against an explicitly configured,
versioned catalog. It does not infer a curriculum from teaching units, enrolments,
or historical unit IDs. A completed **planning check** is not a degree audit,
admission decision, or guarantee of enrolment or future availability.

Deploy the migration before the companion frontend. No catalogs are automatically
seeded in production. An empty catalog returns `[]`; administrators must import
approved curriculum data before students can create plans.

## Administrative catalog import

An operator with server/database access can import one JSON catalog atomically:

```sh
bundle exec rails db:migrate
bundle exec rake 'courseflow:import[path/to/approved-catalog.json]'
```

For a disposable test/demo environment only:

```sh
bundle exec rake 'courseflow:import[docs/courseflow/sample-catalog.json]'
```

The included `DEMO-CF`, version `QA-2026`, is fictional test data and represents
no actual qualification or institution. Importing it is an explicit operator
action, never part of application startup or production seeds.

The JSON object has exactly `code`, `name`, `version`, `elective_count`, and
`units`. Codes are uppercase ASCII letters/digits, `_`, or `-`, starting with a
letter/digit. Course codes and versions are at most 40 characters; names at most
200. The file limit is 1 MiB. Each of 1–240 units has exactly:

```json
{"code":"DEMO102","name":"Demo follow-on study","required":true,"prerequisites":["DEMO101"],"offered_trimesters":[2,3]}
```

Unit codes are at most 20 characters and unique within the catalog.
`required` is a JSON boolean. `prerequisites` contains unique existing codes;
cycles are rejected. Every listed prerequisite must be planned in an earlier
year/trimester. `offered_trimesters` is a nonempty unique subset of integers
`1`, `2`, `3`. `elective_count` is a nonnegative JSON integer specifying the
exact number of non-required units needed. Impossible counts, including required
units whose transitive optional prerequisites exceed the elective allowance,
are rejected. Required prerequisite chains longer than 60 study periods are
rejected. Import validation does not prove that every combination of elective
choices and study periods is feasible; the planner evaluates the chosen plan.

A `(code, version)` is immutable from its first import. An identical import is
idempotent; changed data must use a new version. Existing plans therefore retain
their original rules without a race between catalog editing and saving. There
is no public catalog mutation API. Catalog deletion is restricted while maps
reference it. Future rule types (credit points, substitutions, transfer credit,
corequisites, majors, exclusions, actual timetable capacity) need an explicit
schema and validator change; they must not be represented as supported checks.

## Authenticated endpoints

All paths below start with `/api/courseflow` and use the application's existing
authentication headers. All responses are `Cache-Control: private, no-store`.

| Method | Path | Result |
| --- | --- | --- |
| GET | `/courses` | All configured catalogs, including units and rules |
| GET | `/courses/:id` | One catalog |
| GET | `/maps` | Current user's complete maps, newest updated first |
| GET | `/maps/:id` | Current user's complete map |
| POST | `/maps` | Create private map, HTTP 201 |
| PUT | `/maps/:id` | Atomically replace complete plan |
| DELETE | `/maps/:id?lock_version=N` | Delete matching version, HTTP 204 |

POST takes exactly these JSON fields:

```json
{
  "course_id": 1,
  "name": "My plan",
  "periods": [{"year":2026,"trimester":1},{"year":2026,"trimester":2}],
  "slots": [{"unit_code":"DEMO101","year":2026,"trimester":1,"position":1}]
}
```

The course ID is the ID returned by the catalog API, never a fixed ID. PUT
requires those same fields plus the `lock_version` from the last response.
The owner derives exclusively from authentication; client `user_id` is rejected.
Course and owner cannot change on an existing map. Other users' maps return 404
for reads, updates, and deletes, including requests by staff and administrators.

Names are nonblank strings of at most 200 characters. Periods are explicit so
empty trimesters survive reload: 1–60 unique `{year, trimester}` objects,
integer year 2000–2200, trimester 1–3. Slots are at most 240 objects with exactly
`unit_code`, `year`, `trimester`, `position` (integer 1–4). Every slot belongs to
a declared period and the chosen catalog. Duplicate unit codes and occupied
positions are invalid. Numeric strings, floats, booleans, extra fields, and
malformed structures are rejected instead of coerced.

A map response contains `id`, `course_id`, `name`, `lock_version`, `periods`,
`slots`, `issues`, `complete`, and ISO 8601 `updated_at`. `issues` contains
`{code, message, unit_code?}` with codes `missing_required`, `elective_count`,
`prerequisite`, and `unavailable_trimester`. Incomplete plans can be saved;
`complete` means only that these configured planning checks return no issues.

Shape errors, malformed JSON and unknown course/unit IDs return 422 with `error`
and optional `details`.
Authentication failures use the application's existing 419 response. Missing or
unowned map IDs return 404. Stale updates/deletes return 409: the client must
retain unsaved work and explicitly reload before retrying. A stale request
never overwrites or partially removes the saved plan. Periods and slots are
stored together in one row with optimistic locking and foreign keys.

## Validation

```sh
bundle exec rails test test/models/courseflow_test.rb test/api/courseflow_api_test.rb
```

Tests cover catalog validation and immutability, owner isolation across roles,
authentication, atomic invalid/stale writes, explicit empty periods, strict JSON
types and limits, planning checks, save/reload and delete conflict handling.
