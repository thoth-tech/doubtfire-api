# FILE-S01 upload security threat model

Date: 27 August 2026

## Scope

This review covers the task-submission and task-comment attachment paths that
accept student-controlled files. The protected assets are another student's
work, task state and submission history, worker capacity, storage capacity,
server-side file paths, and identifiers or submitted content that could enter
logs.

The relevant trust boundaries are:

1. an unauthenticated client entering the authenticated API;
2. an authenticated student crossing into another project;
3. multipart metadata crossing into server-side MIME, extension and archive
   validation;
4. a validated temporary upload crossing into task-owned staging storage and a
   background job; and
5. request and validation data crossing into application logs.

## Threats and verified controls

| Threat | Expected control | Automated evidence |
| --- | --- | --- |
| Raw API submission without a session | Authentication rejects before task or storage work | `unauthenticated direct API upload is rejected with 419` |
| Cross-project POST, download or history access | Exact endpoint contract rejects the request; POST creates no task, submission, job or file | Three `student cannot ... another student` tests |
| Misleading extension, MIME or signature | Server-side allow-list and libmagic/PDF/archive validation reject the payload | MIME, signature, malformed-file and unsupported-extension tests |
| Archive traversal or resource amplification | Normalized archive paths plus entry-count, compression-ratio and uncompressed-size limits | ZIP traversal and resource-limit tests |
| Unsafe filename | Server-side path and filename sanitization | traversal, control-character and Unicode tests |
| Duplicate submission while work is queued | Task lock and queued-directory state reject the later request without additional state, payload or job | `sequential duplicate upload is blocked while first submission is queued` |
| Rejected input creates owned staging artifacts | Validation runs before state transition and staging | `early MIME rejection creates no task-owned staging artifacts` |
| Submission or attachment data leaks through reviewed log paths | Safe markers use internal ids and omit content, email, username and client filenames | three log-privacy tests |
| Deleted comment attachment remains retrievable | Model/API deletion removes the owned file and subsequent lookup returns 404 | comment attachment retention tests |

## Deliberate limits

The suite does not claim to prove all FILE-S01 risks are closed. In particular:

- The duplicate test is sequential. It does not synchronize two independent
  database connections at the row lock and therefore is not a true race test.
- Cleanup is proven only for rejection before staging. A controlled copy/move
  failure after staging and an abandoned worker are not injected by this suite.
- Archive controls bound individual uploads, but the suite does not prove a
  per-user storage quota or request-rate limit across many completed uploads.
- Log assertions cover submission validation and task-comment attachments, not
  every historic file-related endpoint in the application.

These limits are recorded as follow-ups in `FILE-S01-security-findings.md` and
must not be represented as passing evidence.
