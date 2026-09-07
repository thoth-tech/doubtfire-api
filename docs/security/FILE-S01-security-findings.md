# FILE-S01 security findings and integration recommendation

Date: 27 August 2026

## Disposition

| Finding | Status | Evidence or follow-up |
| --- | --- | --- |
| Cross-project submission could create work before authorization | Verified | Exact 401 contract plus zero task, `TaskSubmission`, Sidekiq-job and storage deltas |
| Client extension or declared MIME could bypass content validation | Verified | API and `FileHelper` rejection tests assert exact MIME/extension outcomes |
| Unsafe ZIP paths or resource-amplifying archives | Verified | Traversal, entry-count, compression-ratio and total-uncompressed-size tests |
| A later duplicate could enqueue or store more work while processing | Verified for sequential duplicate | The test asserts one first-job/one first-payload and no second-request side effects |
| True simultaneous duplicate race | Open | Add two independent sessions/connections synchronized immediately inside the submission lock; assert one 201, one 403, one job and one payload |
| Rejected input could leave task-owned staging data | Verified before staging | Exact task-owned temporary, `new` and `in_process` paths remain absent after MIME rejection |
| Failure after staging or abandoned worker could leave data | Open | Inject a controlled failure after the first copy/move using isolated roots, define the cleanup contract, and assert owned paths are removed or recovered |
| Reviewed submission and comment-attachment logs expose content or student identifiers | Verified | Tests require exact 403/201 outcomes, safe markers, and absence of content, email, username and client filename; authentication and comment audit logging now use `user_id` |
| Repeated completed uploads could exhaust aggregate storage | Open | Define and test a per-user/unit quota or rate-limit policy; current evidence covers per-archive limits only |
| Comment attachment survives deletion | Verified | Direct model deletion, API deletion and subsequent 404 are covered |

## Integration recommendation

Merge the test and logging-sanitization changes after the exact security test
file and normal required CI checks pass. The evidence supports the verified
rows above. It does **not** support closing FILE-S01 as though true concurrent
races, post-staging cleanup and aggregate storage exhaustion were tested.

Track the three open findings explicitly in the security objective. If the
ticket's acceptance criteria require every one of them before closure, keep the
ticket in progress even after this pull request merges.
