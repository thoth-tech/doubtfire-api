# Student Peer Progress API

## Route and authorisation

`GET /api/projects/:id/task_def_id/:task_definition_id/peer_progress`

The route is restricted to the authenticated student who owns the active,
enrolled project. The unit and target grade are derived on the server. The task
must belong to that unit, be applicable to the student's target grade, and be
released for that project. The browser cannot select a peer cohort.

Every response has `Cache-Control: private, no-store`.

## HTTP 200 response contract

Authorised business states use the same allowlisted response shape:

| Field | Type | Nullable | Meaning |
| --- | --- | --- | --- |
| `task_definition_id` | Integer | No | Requested task definition. |
| `unit_id` | Integer | No | Unit derived from the authenticated project. |
| `target_grade` | Integer | Yes | Valid server-derived grade, or `null`. |
| `submitted_percentage` | Number | Yes | Compatibility metric: other students with a task file upload, quantised to 10-point buckets. |
| `completed_percentage` | Number | Yes | Compact-display metric: other students whose snapshot status is exactly `complete`, quantised to 10-point buckets. |
| `status_distribution` | Array | Yes | Ordered, quantised full-lifecycle distribution, or `null` when it cannot safely be released. |
| `distribution_available` | Boolean | No | Whether `status_distribution` is present. |
| `distribution_unavailable_reason` | String | Yes | Safe machine reason when detailed data is absent. |
| `is_suppressed` | Boolean | No | The entire aggregate is hidden because the cohort is below the configured floor. |
| `is_stale` | Boolean | No | The stored snapshot is older than the configured window. |
| `is_feature_enabled` | Boolean | No | Whether the unit has enabled peer progress. |
| `is_user_enabled` | Boolean | No | The authenticated user's saved `display_peer_progress` preference. |
| `last_updated_at` | String | Yes | Snapshot time as UTC ISO 8601, or `null`. |
| `unavailable_reason` | String | Yes | Safe machine reason when compact data is absent. |
| `unavailable_message` | String | No | Empty on compact success; otherwise neutral user-facing copy. |

Normal response example:

```json
{
  "task_definition_id": 12,
  "unit_id": 5,
  "target_grade": 2,
  "submitted_percentage": 60.0,
  "completed_percentage": 10.0,
  "status_distribution": [
    { "status": "not_started", "percentage": 20.0 },
    { "status": "complete", "percentage": 10.0 },
    { "status": "need_help", "percentage": 0.0 },
    { "status": "working_on_it", "percentage": 20.0 },
    { "status": "fix_and_resubmit", "percentage": 10.0 },
    { "status": "feedback_exceeded", "percentage": 0.0 },
    { "status": "redo", "percentage": 10.0 },
    { "status": "discuss", "percentage": 0.0 },
    { "status": "ready_for_feedback", "percentage": 20.0 },
    { "status": "demonstrate", "percentage": 0.0 },
    { "status": "fail", "percentage": 10.0 },
    { "status": "time_exceeded", "percentage": 0.0 },
    { "status": "assess_in_portfolio", "percentage": 0.0 },
    { "status": "attention_required", "percentage": 0.0 },
    { "status": "rediscuss", "percentage": 0.0 }
  ],
  "distribution_available": true,
  "distribution_unavailable_reason": null,
  "is_suppressed": false,
  "is_stale": false,
  "is_feature_enabled": true,
  "is_user_enabled": true,
  "last_updated_at": "2026-08-24T03:15:00Z",
  "unavailable_reason": null,
  "unavailable_message": ""
}
```

The 15 status entries are always ordered by canonical `TaskStatus` ID:

1. `not_started`
2. `complete`
3. `need_help`
4. `working_on_it`
5. `fix_and_resubmit`
6. `feedback_exceeded`
7. `redo`
8. `discuss`
9. `ready_for_feedback`
10. `demonstrate`
11. `fail`
12. `time_exceeded`
13. `assess_in_portfolio`
14. `attention_required`
15. `rediscuss`

A missing task row counts as `not_started`. Each enrolled project contributes
to exactly one stored status for a task. Before any public calculation, the API
subtracts the authenticated student's project, status, and upload contribution.
All percentages therefore describe other students, never a cohort containing
the viewer.

## Availability reasons

`unavailable_reason` is one of:

- `user_disabled`
- `feature_disabled`
- `target_grade_unavailable`
- `snapshot_unavailable`
- `insufficient_cohort`
- `aggregation_incomplete`
- `stale`

`distribution_unavailable_reason` repeats the applicable compact reason, or is:

- `detailed_data_unavailable` when a pre-migration/incomplete snapshot has no
  valid lifecycle aggregate;
- `privacy_protection` when compact metrics are safe but the combined detailed
  vector is not safe to release.

The API never states which status caused detailed privacy suppression.

## Privacy and quantisation

Raw whole-cohort size, exact uploaded count, completed count, and per-status
counts are internal-only. They are never included in the student response.
`PeerProgressViewerPolicy` first subtracts the authenticated viewer from all
three exact aggregates. The privacy floor and every quantisation/policy check
then run over the remaining peers.

`DF_PPI_MINIMUM_COHORT_SIZE` must be at least
`PeerProgressApi::MINIMUM_SAFE_COHORT_SIZE` (`21`). Cohorts below the configured
value return `is_suppressed: true` and no percentages or distribution. The
configured minimum is a **remaining-peer** floor: with the default of 21, a
stored cohort needs at least 22 active projects including the viewer. Empty and
small peer cohorts use the same response state.

Public percentages are independently rounded to the nearest 10 percentage
points. With 21 remaining peers, a single compact bucket maps to at least two
possible peer counts. Because the viewer is absent from those counts, their
knowledge of their own status or upload cannot collapse that ambiguity.
Therefore `0.0` does not prove no peer is in a state, and `100.0` does not prove
every peer is.

Independent buckets are not sufficient for a multi-status histogram because
the buckets can constrain one another. Before returning `status_distribution`,
`PeerProgressDistributionPolicy` assumes the observer already knows the exact
cohort size and computes the feasible raw-count range for every status given all
15 buckets and the requirement that counts sum to the cohort. The whole vector
is returned only if every status retains at least two feasible raw counts.
Otherwise the vector is withheld with `privacy_protection`; compact metrics can
remain available.

Because each status is independently quantised, a public distribution is a
visual estimate and its percentages are not generally guaranteed to sum to 100.

## User preference

`users.display_peer_progress` is `true` by default and non-null for new and
existing users. It is exposed by `Entities::UserEntity`, including authentication
responses, and can be saved through the normal profile endpoint:

```http
PUT /api/users/:id
Content-Type: application/json

{
  "user": {
    "display_peer_progress": false
  }
}
```

When false, the peer-progress endpoint returns `is_user_enabled: false`, reason
`user_disabled`, and no peer metrics. Saving `true` re-enables it.

## Freshness and grade changes

`DF_PPI_STALE_AFTER_HOURS` must be a positive integer. A stale snapshot returns
no metrics. Each project records `target_grade_changed_at`; a snapshot calculated
before the current target-grade selection is treated as unavailable until the
next aggregation.

Missing or invalid configuration fails closed with HTTP 503 once an enabled
user, unit, valid grade, and snapshot require the configuration.

If the viewer's persisted task changed after `snapshot.calculated_at`, the API
returns `snapshot_unavailable` rather than subtracting a current status/upload
from an older aggregate. Snapshots created before exact `submitted_count` and
15-status data were introduced return `aggregation_incomplete` until the next
aggregation.

## Error responses

- `200`: authorised normal, preference-off, disabled, suppressed, stale, or
  otherwise unavailable business state.
- `404`: the project/task cannot safely be exposed to this caller. Unknown IDs,
  wrong ownership, wrong role, inactive enrolment/unit, unreleased tasks, and
  inapplicable tasks share the same message.
- `419`: authentication failed through the existing OnTrack flow.
- `503`: required peer-progress configuration is missing or invalid.

## Demo data

The all-features demo is triple-guarded: Rails development, database exactly
`doubtfire-all-features-demo`, and `DF_DEMO_DATA_PROFILE=all-features`.

`db:all_features_demo` creates a 25-student total cohort (24 remaining peers for
the demo viewer) with visible `not_started`,
`working_on_it`, `ready_for_feedback`, `fix_and_resubmit`, `redo`, `complete`,
and `fail` states. It uses the production aggregation service.

`db:all_features_demo_verify` is read-only and fails unless the preference and
unit feature are enabled, the task is released, the snapshot is fresh and leaves
enough peers after viewer subtraction, the true completed metric is available,
and the same production viewer/public policies release all 15 status keys with
the seven showcase states visible.

`db:ppi_sample_data` creates the larger two-unit dashboard dataset under the
same guards and validates every generated snapshot with the same distribution
policy.
