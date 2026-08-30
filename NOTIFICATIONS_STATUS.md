# Unified Notifications - Status

> Historical implementation record. The unified in-app, email and Web Push
> paths described as future stages below are now implemented on the integration
> branch. Use `NOTIFICATIONS.md`, `docs/notifications/push-setup.md`, and the
> review evidence under `docs/notifications/reviews/` for current operation and
> release status.

Feature: unified notifications (in-app, email, push) for OnTrack.
Base: `11.0.x`. Branch: `feature/notifications` (api and web), off `origin/11.0.x`.
Merge and demo target: `integration`.

The lead runs all commits, merges, and pushes. This file records what is staged
in the working tree and the exact commands to run.

## Architecture

One hub, many channels:

    event happens -> NotificationService.notify(...) -> in-app record
                                                     -> email job -> mailer
                                                     -> push job -> Web Push (when configured)

A single category toggle gates every channel. The three existing user
preference columns (`receive_task_notifications`, `receive_feedback_notifications`,
`receive_portfolio_notifications`) map onto the notification `type`. If a
category is off, the notification is suppressed on all channels, including
in-app. Per-channel granularity (a type x channel matrix) is deferred to v2.

## Stage 1 (done, staged in api working tree)

New files:
- `app/models/notification.rb` - hub model. Types task/feedback/portfolio/extension/general. `unread` and `recent_first` scopes, `mark_read!`.
- `db/migrate/20260722000001_create_notifications.rb` - notifications table (user_id, notification_type, message, link, read_at, timestamps). Ticket EN-F01 later added `event` and widened `message` to text.
- `app/services/notification_service.rb` - the fan-out entry point. Respects the category preference, creates the in-app record, and queues ID-only email and push jobs.
- `app/services/push_notification_service.rb` - push channel delivery. No-op until VAPID keys exist, so it is safe to run today.
- `app/api/notifications_api.rb` - REST endpoints (list, unread_count, mark read, mark all read, delete). All scoped to `current_user`, so no IDOR.
- `app/api/entities/notification_entity.rb` - response shape.
- `app/views/notifications_mailer/single_notification.{html,text}.erb` - email templates.

Changed files:
- `app/api/api_root.rb` - mount `NotificationsApi` and add auth, both in a `# Notifications feature` block.
- `app/models/user.rb` - `has_many :notifications` in a `# Notifications feature` block.
- `app/mailers/notifications_mailer.rb` - new `single_notification` method.
- `app/api/users_api.rb` - real bug fix (see below).

## Bug review result

- `users_api.rb:69-71` copy-paste bug: REAL, fixed. The three lines all wrote the
  portfolio key and read top-level params instead of the nested `:user` hash, so
  the nil-default never applied. Replaced with a loop over the three keys on
  `params[:user]`.
- "portfolio emails gated by the wrong flag": NOT a bug. `receive_portfolio_notifications`
  is enforced at `lib/tasks/generate_pdfs.rake:151`, which gates the
  `portfolio_ready` and `portfolio_failed` emails. Line 75 of
  `portfolio_evidence.rb` gates a task email (`task_pdf_failed`) by the task flag,
  which is correct. No change made here.

## Endpoints

    GET    /api/notifications?unread_only=false
    GET    /api/notifications/unread_count
    PUT    /api/notifications/:id/read
    PUT    /api/notifications/read_all
    DELETE /api/notifications/:id

## How to raise a notification (for teammates wiring events)

    NotificationService.notify(
      user: project.student,
      type: 'feedback',
      event: 'task_comment_created',
      message: "New feedback is ready for #{task_definition.name}.",
      link: "/#/projects/#{project.id}"
    )

`event:` is required. It is the specific thing that happened, in
lower_snake_case. See NOTIFICATIONS.md for how it differs from `type:`.

## Verification (run in the container, host Ruby is 2.6)

The compose files live in `doubtfire-deploy/development/`. Run all of these from
there. See doubtfire-deploy/RUNNING-LOCALLY.md.

    cd doubtfire-deploy/development
    COMPOSE="docker compose -f docker-compose.yml -f docker-compose.local-paths.yml"

1. Rebuild and start (11.0.x needs Ruby 3.4 and Node 22):
   `$COMPOSE up -d --build`
2. Only if migrate fails with a stale-DB error (task_prerequisites doesn't exist), reset first:
   `$COMPOSE run --rm --no-deps doubtfire-api bash -c "bundle exec rake db:drop db:create db:schema:load && bundle exec rails db:environment:set RAILS_ENV=development && bundle exec rake db:populate"`
3. Migrate (updates `db/schema.rb`, commit that change after migrating):
   `$COMPOSE exec doubtfire-api bundle exec rails db:migrate`
4. Lint the new code:
   `$COMPOSE exec doubtfire-api bundle exec rubocop app/models/notification.rb app/services app/api/notifications_api.rb app/api/entities/notification_entity.rb`
5. Smoke test: in a rails console, `NotificationService.notify(user: User.first, type: 'general', event: 'smoke_test', message: 'Hello')`, then `GET /api/notifications` as that user. A mail file should also appear in `doubtfire-deploy/data/tmp/mails/`.

Still to add for Stage 1 completion (good first tasks, run in container):
- `test/factories/notifications_factory.rb`
- `test/models/notification_test.rb` and `test/api/notifications_api_test.rb`

## Open decisions for the lead

1. VAPID keys: where in `doubtfire-deploy` secrets, and who generates them. Suggest
   env vars `DOUBTFIRE_VAPID_PUBLIC_KEY` and `DOUBTFIRE_VAPID_PRIVATE_KEY`. Blocks
   the Stage 4 push send path. Push code is safe to run before this is set.
2. Notification email sender: set `institution[:email_sender]` in config, or accept
   the `noreply@doubtfire.local` fallback for now.
3. `api_root.rb` mount ordering: agree with the cross-unit and peer-progress leads.
4. In-app suppression when a category is off is implemented as decided. Confirm.
5. v1 trigger events: which events create notifications. The mechanism is done;
   this is a scoping task for the team.

## Remaining stages

- Stage 2 (web): re-home the salvaged #353 header bell to Angular 22 (standalone: false,
  routerLink not uiSref, @if/@for), add a notifications API service, register in a
  `// Notifications feature` block in `doubtfire-angular.module.ts`.
- Stage 3 (web): settings toggles for the three preference booleans (API already exists).
- Stage 4 (api + web + deploy): Web Push. push_subscriptions table and endpoint,
  web-push gem, VAPID keys; SwPush subscribe and permission UI; service worker
  push and notificationclick handlers.
- Stage 5: verification per stage.
