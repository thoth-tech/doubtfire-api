# Optional automatic Teams announcements

This connection copies approved Teams announcements into Unit Hub. It is off by default. It uses a university-managed Microsoft application in the background; students continue using the existing OnTrack sign-in. The connection does not change SAML/Entra sign-in, create student accounts or infer enrolment from Teams names.

OnTrack enrolment decides which unit updates a student receives. Microsoft application consent separately allows the worker to read approved Teams data. Signing in through Microsoft does not grant that permission by itself. [Microsoft permissions and consent](https://learn.microsoft.com/en-us/entra/identity-platform/permissions-consent-overview)

## University setup

1. Apply the Unit Hub migrations through `20260914000002` and deploy the matching API and worker code. This adds source metadata and sync checkpoints without changing manual announcements.
2. Have the university administrator approve the data use, exact unit offerings, source channels and staff publishers. Map only channels whose content every student enrolled in that unit offering is entitled to see. Never map a private staff channel or a restricted student subgroup.
3. Register a university-managed, single-tenant Microsoft application. Prefer `ChannelMessage.Read.Group` through the university-approved Teams app installation and resource-specific consent process. This permission is supported for listing and retrieving channel messages. Resource-specific consent limits the grant to approved Teams resources; the application mapping narrows it to particular channels. Broader `ChannelMessage.Read.All` requires a deliberate university decision and appropriate consent. [List permissions](https://learn.microsoft.com/en-us/graph/api/channel-list-messages?view=graph-rest-1.0), [Get-message permissions](https://learn.microsoft.com/en-us/graph/api/chatmessage-get?view=graph-rest-1.0), [Teams resource-specific consent](https://learn.microsoft.com/en-us/microsoftteams/platform/graph-api/rsc/resource-specific-consent)
4. Store the application client secret through the deployment's protected secret process. The worker uses the tenant-specific client credentials flow with `https://graph.microsoft.com/.default`. No student token or extra personal account-linking step is used. This implementation supports Microsoft's public-cloud endpoints only. [Client credentials flow](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-client-creds-grant-flow)
5. Configure the values below. Use the actual OnTrack **unit offering database ID**, a verified team/channel pair, and the Entra object IDs of approved staff publishers. A unit code, email address or display name is not an identity mapping.

```dotenv
DF_TEAMS_ANNOUNCEMENTS_ENABLED=true
DF_TEAMS_TENANT_ID=<university-tenant-guid>
DF_TEAMS_CLIENT_ID=<approved-application-guid>
DF_TEAMS_CLIENT_SECRET=<application-secret>
DF_TEAMS_CHANNEL_MAPPINGS=[{"unit_id":123,"team_id":"<team-guid>","channel_id":"19:<channel-id>@thread.tacv2","publisher_ids":["<approved-staff-object-guid>"],"student_visible":true}]
```

Replace every placeholder. Keep the mapping JSON on one line without surrounding quotes when using the supplied production validator. Disabled defaults are `DF_TEAMS_ANNOUNCEMENTS_ENABLED=false` and `DF_TEAMS_CHANNEL_MAPPINGS=[]`.

The API and main worker both need the enabled flag, tenant ID and mapping JSON. **Only the main worker receives the client ID and secret.** Do not pass application credentials to the web build, student browser, PDF worker, migration service or fictional demo. The deployment repository provides the service isolation and validation rules.

Between one and twenty mappings are allowed when enabled. Every mapping requires `student_visible:true` and one to one hundred approved publisher IDs. Invalid identifiers, duplicate exact mappings and missing approval fields are rejected. The visibility declaration is an operator's explicit assertion; the importer does not verify that the Teams membership list equals OnTrack enrolment. University review of this mapping remains necessary.

## Operation and boundaries

`SyncTeamsAnnouncementsJob` is scheduled every five minutes. To request a run immediately, execute this inside the configured main worker:

```sh
bundle exec rake teams:sync_announcements
```

The command reports status and counts without printing credentials or message contents. The Unit Hub `teams_sync: configured` label means a valid mapping exists. It does not prove consent succeeded or that the most recent import completed.

Each run reads at most two pages of fifty recent root messages per mapping, then revisits up to twenty-five older imported messages, starting with those checked longest ago. The listing API excludes replies by default; the importer also rejects replies, system/application messages and posts from anyone outside the approved publisher list. Returned team/channel identity and individual lookup IDs must match the requested source. This does not copy general student discussion. Older messages that were never imported are outside this bounded initial import. [Microsoft channel listing behaviour](https://learn.microsoft.com/en-us/graph/api/channel-list-messages?view=graph-rest-1.0)

Graph requests use fixed HTTPS Microsoft hosts and do not follow redirects. Pagination links must remain on the exact configured channel messages path. Each response is capped at 2 MiB; the client has a 180-second request budget checked before requests and during body reads, with five-second connection/write and ten-second read timeouts. A blocked transport operation remains subject to its own timeout.

HTTP 429 triggers a persisted cooldown across mappings and worker runs. Numeric `Retry-After` values are bounded to 60–86,400 seconds; absent or unsupported values use 300 seconds. No immediate retry loop is used.

## Copies, changes and removal

Imported posts have stable source IDs and are marked `microsoft_teams` / externally managed. Repeated imports update the same record. Source identities are separate from manual announcements, and the normal staff API refuses to edit or delete imported copies. Staff make those changes in Teams.

The importer converts HTML to plain text. It does not fetch attachments, execute markup or load external images. Source links must match the configured tenant, team, channel and message. Stored links are rebuilt as a Teams message link with only the verified team and tenant parameters. The serializer does not expose source keys or application credentials.

A post missing from a limited recent listing is **not** assumed deleted. Older imported records are checked individually. An explicit deleted message or individual 404/410 unpublishes that copy. A missing source channel, HTTP 401/403, or a token-endpoint HTTP 400 unpublishes affected mapped copies. Temporary network/server failures retain previously verified copies only until their seven-day expiry. Older provider versions do not overwrite newer stored text.

Disabling the feature, removing a mapping or changing its tenant, unit, channel or approved publishers changes the visibility rules immediately on subsequent API requests. Apply metadata changes to the API and worker together. Both student and staff lists enforce these rules. An unchanged source channel has a separate stable identity, allowing old posts to be rechecked under a changed publisher policy before becoming visible again. A new source channel starts its own bounded import.

Operators can inspect `TeamsAnnouncementSyncState` for `status`, `last_attempt_at`, `last_succeeded_at` and `next_attempt_at`. Status values are `pending`, `synced`, `failed` and `throttled`. Check these in an authorised operational session; do not publish message bodies, tokens or secrets in issue comments. Sync checkpoints and imported rows are removed with their unit.

## Verification and remaining scope

Automated verification uses mocked Microsoft responses and an isolated seeded test database. No real university application credentials or tenant connection were available during implementation. Before enabling a university deployment, verify an approved staff post appears for the correct enrolled student, then test an edit, deletion, an unapproved publisher, another unit's student and a disabled mapping. Confirm the deployed worker and API share the same tenant/mapping metadata.

HelpHub and class times remain structured sessions maintained by assigned OnTrack teaching staff. This importer does not infer timetable dates or meeting schedules from free-form posts. Automatic timetable integration needs an approved authoritative source and separate implementation. Existing calendar subscription consent, unit exclusions and the distinction between one-off copies and subscriptions are unchanged.
