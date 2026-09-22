# Contributing to OnTrack API

The API is a Rails application with Grape endpoints, Active Record models and
Sidekiq jobs. Start with this guide for any API ticket. Notification-specific
rules are in [the notifications guide](docs/notifications/CONTRIBUTING.md).

## Contents

- [Setting up](#setting-up)
- [Repositories and branches](#repositories-and-branches)
- [Project structure](#project-structure)
- [Unit testing](#unit-testing)
- [Commits and pull requests](#commits-and-pull-requests)
- [Review and keeping up to date](#review-and-keeping-up-to-date)

## Setting up

Use the deploy repository's [local setup guide](https://github.com/ontrack-features-t2-2026/doubtfire-deploy/blob/11.0.x/RUNNING-LOCALLY.md)
for the sibling checkout layout, Docker build and ordered database startup.
For current ticket work, use `11.0.x` in all three repositories; the historical
integration revisions in the demo instructions describe the recorded demo.
The source mounted into a container determines the code it runs.

Run Ruby commands inside the API container. The [Gemfile](Gemfile) requires
Ruby 3.4. When using the local-path overlay described in that setup guide,
open a shell from `doubtfire-deploy/development`:

```sh
docker compose -p notifications-demo -f docker-compose.yml -f docker-compose.local-paths.yml exec doubtfire-api bash
```

Keep that project name and both Compose files on later commands. The service
is `doubtfire-api`, not `api`. The combined stack exposes the web at
<http://localhost:4400>, the API at <http://localhost:3200> and Mailpit at
<http://localhost:8225>. The base-only stack uses different ports.

Four setup failures to recognise:

- **Wrong remote:** current team work is in `ontrack-features-t2-2026`, with
  `11.0.x` as the integration branch. Check `git remote -v` before fetching or
  pushing. Do not assume an upstream fork is the team repository.
- **403 when pushing:** check membership of the team's write-access group with
  the repository maintainer. Repeating a push does not grant access.
- **Windows database rename errors:** the current Compose files use a named
  database volume. Do not replace it with a host bind mount; the old host-share
  setup produced `Tablespace is missing for a table` during population.
- **Branch casing on macOS:** a case-insensitive filesystem can display stale
  `Feature/` refs. Check server spelling with `git ls-remote --heads origin`.

The normal development worker consumes `mailers` and `notifications` only.
It intentionally does not process submission/PDF jobs that require supporting
services. See the deploy guide before testing those workflows.

## Repositories and branches

| Repository | Responsibility |
| --- | --- |
| [doubtfire-api](https://github.com/ontrack-features-t2-2026/doubtfire-api) | Rails/Grape API, models, jobs and API documentation |
| [doubtfire-web](https://github.com/ontrack-features-t2-2026/doubtfire-web) | Angular client |
| [doubtfire-deploy](https://github.com/ontrack-features-t2-2026/doubtfire-deploy) | Local stacks, production configuration and release procedures |

Create a ticket branch from the current remote integration branch. For example:

```sh
git fetch origin
git switch -c fix/my-ticket origin/11.0.x
```

Use the branch name agreed for your ticket, and record it with the work. Do not
create a branch beneath an existing branch name: Git cannot hold both `fix/name`
and `fix/name/child`. Open pull requests against the team repository's
`11.0.x`. The former notifications integration branch has been merged.

## Project structure

| Path | What belongs here |
| --- | --- |
| `app/api/` | Grape routes, parameter declarations and endpoint authorisation |
| `app/api/entities/` | Public response serializers; check field exposure here |
| `app/models/` | Active Record relationships, validations and domain behaviour |
| `app/services/` | Shared application workflows and external integrations |
| `app/sidekiq/` | Background jobs; verify their queue is consumed |
| `app/mailers/`, `app/views/` | Email delivery and HTML/plain-text alternatives |
| `lib/tasks/` | Rake maintenance, population and import tasks |
| `test/` | Minitest cases, factories and shared test helpers |
| `config/` | Runtime settings, job schedules and database configuration |
| `db/migrate/`, `db/schema.rb` | Database migrations and generated schema |

## Unit testing

The API suite uses Minitest. Put regression tests under `test/`, mirroring the
application path. Use Vitest for work in the web repository.

Run these inside the API container. Check that `DF_TEST_DB_DATABASE` names a
**disposable test database**, separate from development and production. The
local-path overlay supplies `doubtfire-notifications-test`. Population deletes
and recreates data, so do not point it at a database you need to keep.

```sh
# Once for a new disposable test database; seeds the roles/units tests expect.
RAILS_ENV=test SKIP_OVERSEER_IMAGE_PULL_ON_POPULATE=true bundle exec rake db:populate

# Run the file affected by your change.
bundle exec rails test test/api/settings_test.rb
bundle exec rails test test/models/break_test.rb

# Select a named case (avoids a line number becoming stale).
bundle exec rails test test/api/settings_test.rb -n test_authenticated_settings_reject_unauthenticated_requests

# Full suite when the change warrants it, or when reproducing CI.
bundle exec rails test
```

`test/test_helper.rb` fails early if required seed data is missing. A migrated
but empty database is insufficient. The command above skips pulling the Overseer
runner image; tests that exercise that integration require its supporting stack.
The historical `test:setup` shortcut
currently refers to a removed JPlag task; use the population command above.
Run the targeted test before the fix to
show the failure, then after it to show the regression is covered. Include
actual counts and failures in the PR, including unrelated existing failures.

Mail development checks use Mailpit. When `DF_SMTP_ADDRESS` is absent, Rails
writes mail to files; the Compose mount puts them in
`doubtfire-deploy/data/tmp/mails/`. Read both HTML and text alternatives.
For push, use the [local testing guide](docs/notifications/testing-push-locally.md).

## Commits and pull requests

Use `type(scope): summary`, such as `fix(settings): preserve feature defaults`.
Typical types are `feat`, `fix`, `docs`, `test`, `refactor` and `chore`.
Stage only your change and commit it; push the ticket branch for review.

Keep the PR focused on one behaviour or a closely related group of tickets.
State the problem, resulting behaviour and verification. Every PR records the
exact repository combination it was checked against:

```text
Tickets: <ticket IDs>
Built against:
  doubtfire-api    <branch> <full commit SHA>
  doubtfire-web    <branch> <full commit SHA>
  doubtfire-deploy <branch> <full commit SHA>
Tests: <commands and actual results>
Manual checks / limitations: <what was and was not verified>
```

Use `git branch --show-current` and `git rev-parse HEAD` in each checkout.
Link the PR from the ticket. Do not put credentials, student data or private
message content in logs, screenshots or PR descriptions.

## Review and keeping up to date

Another contributor reviews and the lead merges. Do not merge your own work.
The team's review guide asks for two approvals for migrations, shared delivery
services, configuration, dependencies or files being edited by another ticket;
other isolated changes need one. Check the repository's current review rules.
CI passing does not replace review or the manual checks stated in the PR.
Documentation-only changes may not trigger API CI.

Before opening the PR, fetch `origin` and merge `origin/11.0.x` into your work
branch, resolve conflicts and rerun the affected checks. Do not discard another
contributor's changes to resolve a conflict. Keep PRs targeting `11.0.x` so
reviewers can assess only your work.

Migrations often conflict in `db/schema.rb`; generate the schema from the
combined migrations. Put notification event documentation in separate files
under `docs/notifications/events/`. Keep final newlines in changed files.

If blocked, share the ticket, exact error, attempted command and what you
already checked. Do not claim verification you could not perform.
