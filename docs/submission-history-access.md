# Student Submission History Access

## Purpose

SLR-H01 defines how students may access retained versions of their own previous submissions without exposing another student's submission history or internal storage details.

## Authorisation model

Student access is fail-closed.

A student may retrieve submission-history metadata or download a retained archive only when the request resolves through the signed-in student's exact:

1. project,
2. task definition,
3. task, and
4. submission history belonging to that task.

A submission-history identifier does not grant access by itself.

For student requests, both the project and task must authorise `:get_submission`.

History reads authorise the project or staff unit permission before querying the existing task. They never create a task: an authorised request for a task that has not been created returns the same safe `404` response.

The download route additionally preserves the existing staff path using the unit-level `:provide_feedback` permission.

Invalid and unauthorised project, task-definition, task and history identifiers return the same generic response:

`Submission history is not available`

This prevents callers from using identifier substitution to determine whether another student's history exists.

## Student metadata

Students receive only the metadata required to display retained versions and request an authorised download:

- `id` - only because the authorised download route requires the history identifier
- `version_order` - position in the returned history list, newest first
- `submission_timestamp`
- `status`

The student response does not expose:

- task IDs
- Overseer assessment IDs
- creation metadata not required by the student view
- filesystem paths
- archive paths
- storage implementation details

The existing richer staff metadata contract is unchanged.

## History states

A retained history may have the following states:

### available

The history record exists and its retained archive contains submission files.

### unavailable

The authorised history record exists but its retained archive is missing, removed or otherwise has no available submission files.

The download endpoint returns a safe `404` response for this case.

### processing

`SubmissionHistory.pending?(task)` indicates that a new retained history archive is currently being created.

The metadata endpoint returns HTTP `202` while processing is active. Existing retained histories remain in the response and no synthetic history identifier is created for the pending archive.

## Group submissions

Current group membership is not evidence that a student was entitled to an older group submission.

Historical access is therefore not granted by checking the student's current group.

A student can access history only through their own authorised project and task. If existing immutable data cannot prove historical entitlement, the history remains unavailable to that student.

Supporting historical access for former group members whose history is stored only against another member's task would require a separate immutable entitlement snapshot and is outside SLR-H01.

Existing staff access is unchanged.

## Retention

Submission histories follow the configured unit and archive lifecycle.

SLR-H01 does not guarantee that every submission version remains downloadable for an exact fixed period. Unit archival, deletion and other configured lifecycle operations may make a retained archive unavailable.

For this reason the API reports file availability rather than promising a fixed retention duration.

## Sanitised API examples

### Student metadata

Request:

```http
GET /api/projects/123/task_def_id/45/submission_histories
```

Response:

```json
[
  {
    "id": 901,
    "version_order": 1,
    "submission_timestamp": "1788551000",
    "status": "available"
  }
]
```

### Authorised download

Request:

```http
GET /api/projects/123/task_def_id/45/submission_histories/901/files
```

If the signed-in user is authorised and the retained archive exists, the API returns the submission archive as a binary download with HTTP `200`.

### Missing archive

Response:

```json
{
  "error": "Submission history files are not available"
}
```

HTTP `404`.

### Invalid or unauthorised identifier

Response:

```json
{
  "error": "Submission history is not available"
}
```

HTTP `404`.

## Security properties tested

The API tests cover:

- student's own metadata access
- student's own retained archive download
- existing staff metadata access
- existing staff archive download
- cross-student metadata access
- cross-student archive access
- substituted or invalid project identifiers
- task definitions from another unit
- substituted history identifiers
- histories belonging to another task
- changed current group membership
- missing retained archives
- processing archives
- minimal student metadata

The student metadata and download routes both enforce authorisation server-side.
