# Verified additional notification email

## Scope

An account may register one optional **Additional notification email**. The
institutional/sign-in address remains the primary notification destination. A verified
additional address receives a separate copy of notification-service email; it is never added as a
CC and it never replaces the primary address.

This feature extends `NotificationEmailJob`, the existing single-notification path documented in
`docs/notifications/existing-emails.md`. It deliberately does not copy the separate legacy,
operational, weekly-summary, D2L, communication-rule, or portfolio mailers. Adding the address to
those independent paths would create the duplication risks identified by that audit.

## State and API

`additional_notification_emails` has one row per user and stores the normalised address, a
monotonic verification version, issue/expiry timestamps, and the verified timestamp. It never
stores a verification token or digest. `additional_notification_email_audits` stores only the user,
an allow-listed event, and timestamps; it stores no address, token, notification body, or mail
content.

Authenticated, self-only endpoints:

- `GET /api/users/:user_id/additional_notification_email`
- `PUT /api/users/:user_id/additional_notification_email`
- `POST /api/users/:user_id/additional_notification_email/resend`
- `DELETE /api/users/:user_id/additional_notification_email`

The public completion endpoint is `POST /api/additional_notification_emails/verify`. The signed
token is submitted in the request body. It is never part of an API URL, and `token` is in the
server parameter-filter list. State responses are marked `private, no-store` and expose only
`none`, `pending`, or `verified`, the requested address, and the expiry time.

## Verification and abuse controls

- Links are signed with the Rails secret, purpose scoped, and expire after 24 hours.
- A resend or replacement increments `verification_version`; every earlier link and queued mail
  job becomes stale immediately.
- Verification rechecks the signed version while holding the row lock, closing the
  replacement/verification race.
- A used link returns a conflict; an expired, replaced, or malformed link fails.
- At most three request/resend operations per account are accepted in a rolling one-hour window.
  The limit uses persistent, token-free audit events rather than process memory.
- The address is lower-cased and cannot equal the institutional address case-insensitively.
- Removal destroys the destination, invalidates every outstanding link, and leaves only the
  content-free `removed` audit event.
- Background jobs carry stable database ids and the verification version, never an address, token,
  subject, or notification content.

The verification email points to `/verify_additional_email#token=...`. The web bootstrap captures
that fragment into one-use module memory and removes it with `history.replaceState` before Sentry
or Angular starts. The verification page then POSTs it in the request body. This prevents the
secret from entering browser history, referrers, client telemetry, or API access-log URLs.

## Delivery isolation and preferences

`NotificationEmailJob` rechecks the current category preference and sends the primary message
first. Only after that message is accepted does it enqueue `AdditionalNotificationEmailDeliveryJob`
with notification id, additional-email id, and verification version.

The optional job independently rechecks all of the following at execution time:

1. the destination still belongs to the notification user;
2. it is still verified and has the queued version;
3. it is not equal to the current institutional address; and
4. the current task/feedback/portfolio notification preference still permits delivery.

It then sends a second message using the event's existing safe template. The optional job has its
own retry lifecycle. Its failure or queue hand-off failure is audited and logged using ids and the
exception class only; it cannot fail or retry the already accepted primary message. This avoids
both primary suppression and primary duplication.

## Identity boundary

The profile API treats institution-controlled identity as account data:

- under SAML/AAF/LDAP-style authentication, a changed email is rejected for self-service and
  administrator requests;
- a user cannot change their own student id under any authentication mode;
- under institution-controlled authentication, an administrator cannot forge another user's
  student id; and
- database-auth development installations retain local email editing and administrator
  maintenance of another local account's student id.

Sending the unchanged rolling-client values is accepted, so preferred name and genuine profile or
notification settings continue to save. User serialization exposes
`institutional_identity_managed` and `email_editable` so the web does not infer identity policy
from a role or hostname.

## Deployment order

Deploy this as one ordered change; do not expose the new UI against an API without its schema.

1. Back up and migrate the API database with
   `20260831012000_create_additional_notification_emails.rb`.
2. Deploy/restart the API so the state, verification, and identity-policy endpoints are present.
3. Deploy/restart a Sidekiq worker using `config/sidekiq.yml`. Both verification and optional-copy
   jobs use the existing `mailers` queue, so at least one worker must listen to it.
4. Confirm the configured sender and SMTP provider can deliver the application's domain, then
   deploy the web client.
5. Run a pending -> verified -> copied -> removed smoke test. Confirm a category opt-out between
   the primary and optional job suppresses the optional copy.

Rolling back the web and API code is safe while the two new tables remain. Dropping the tables is a
separate destructive database operation and is not part of an application rollback. Rotating the
Rails secret intentionally invalidates every outstanding verification link.

## Environment verification on 2026-08-31

The available API and worker were configured only for the local Mailpit catcher on port 1025,
using a `.local` sender. Mailpit had no outbound relay/provider configuration. One isolated SMTP
handoff to a reserved `example.test` recipient was accepted and stored by Mailpit; all temporary
database writes were rolled back. No external mailbox delivery was attempted or claimed. See the
Batch 12 evidence handover for the message identifiers and exact blocker.
