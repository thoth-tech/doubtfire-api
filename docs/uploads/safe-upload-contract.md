# Safe upload contract and regression guide

Implements FILE-B01, FILE-F02, FILE-T02 and the repository handover portion of
FILE-MVP01. This guide describes the changes in this PR; release still requires
review and merge. It extends the existing DOCX work (`batch03_docx_*` tests),
FILE-A01 policy by Sandil Sithmaka Bandara Weganthale, FILE-F01 requirement display,
and FILE-S01 security tests rather than replacing them.

## Contract

Authenticated `GET /api/task_comments/upload_policy` returns version 1, categories
with display names, extensions and preview modes, `max_bytes_exclusive: 30000000`
and `max_selection_count: 5`. The browser consumes this response; it must fail
closed for attachments if the response is unavailable. Text comments still work.
There is one file per POST. Five is the browser selection limit, not a server
quota: each selection is confirmed and each request independently validated.

| Context | Accepted formats | Limit / rendering |
| --- | --- | --- |
| Task `csv` / Spreadsheet | CSV, XLS, XLSX | configured per-file maximum (10,000,000 bytes fallback), inclusive; original files retained, download-only notice in PDF |
| Task `code` / Code | existing curated frontend extensions | same task limit; existing code rendering |
| Other task categories | PDF, image, archive | existing configured requirements; `archive` aliases `zip` |
| Chat Document | DOCX | smaller than 30,000,000 bytes; download only |
| Chat Spreadsheet | CSV, XLSX | smaller than 30,000,000 bytes; download only |
| Chat PDF, Image, Audio | exact extensions from policy response | smaller than 30,000,000 bytes; existing conversion and rendering |

FILE-A01's audit described `csv` as an existing task category. Inspection of the
current API instead found only the browser extension list: task-definition
validation, upload validation, and archived-file filtering omitted it. This PR
completes those paths while keeping the stored key `csv`. No data migration is
needed. Spreadsheet originals are not converted to CSV or reduced to one sheet.

Legacy XLS remains available for task requirements with an OLE stream whitelist,
BIFF encryption/macro checks and a spreadsheet parser. New chat XLS is excluded:
save as CSV or macro-free XLSX. Macro-enabled files, embedded objects, executable
files, arbitrary archives in chat, encrypted packages and remote Office content
are excluded. Office hyperlinks may remain; external templates, images and
workbooks are rejected. Validation does not claim malware scanning. Raw PCM is
accepted only in the existing audio conversion path; generic binary is not
accepted for other audio extensions. Browser audio recordings named `blob`
remain supported only when their detected media type is audio/WebM.

`document` remains the task PDF identifier. DOCX is supported in chat, not exposed
as a task requirement by this PR. Code keeps its reviewed list; arbitrary known
extensions are no longer accepted as Code simply because bytes look like text.

## Validation and storage

`CommentAttachmentPolicy` owns the chat policy. `SpreadsheetUploadPolicy` owns
task spreadsheet validation. `FileHelper` retains the shared validators. Files
are checked before permanent storage for size, extension and detected MIME.
Browser-reported MIME is never accepted as evidence of file contents. CSV is
parsed as UTF-8 records; XLSX/DOCX require safe ZIP entries, bounded expansion,
valid content types, valid main XML and safe relationship targets. Task files
are bounded before spreadsheet parsing. Archive protections remain in effect.

The existing project authorization, task-scoped lookup, group access and retry
identifier contract remain intact. Generic attachments use existing ID-based
storage, sanitized metadata and the existing transaction cleanup path. Rejected
uploads stay in Rack-managed temporary storage; no task attachment is created.
A failure after storage removes the stored file before transaction rollback.

Generic downloads always use `Content-Disposition: attachment`, `nosniff` and
the existing no-cache revalidation behavior. They preserve bytes and use an authenticated endpoint.
Old attachments remain accessible under the existing authorization rules.

Errors preserve the existing `error` string and add stable `code` values:
`UPLOAD_EMPTY`, `UPLOAD_TOO_LARGE`, `UPLOAD_EXTENSION_NOT_ALLOWED`,
`UPLOAD_MIME_INVALID`, `UPLOAD_CORRUPT`, `UPLOAD_ENCRYPTED`. Authorization retains
existing 403/404 behavior. Rejections are logged at INFO without client names,
content, emails or server paths. Success is logged only after a comment exists.

## Repeatable regression matrix

Run with the repository's populated test database and normal test environment:

```sh
bundle exec rails test test/lib/batch03_docx_file_helper_test.rb test/lib/spreadsheet_upload_policy_test.rb test/api/comments/batch03_docx_attachment_test.rb test/api/comments/safe_attachment_policy_test.rb
bundle exec rails test test/models/file_helper_test.rb test/api/upload_security_test.rb test/api/comments/comment_test.rb
```

| Acceptance / failure path | Automated coverage |
| --- | --- |
| Task spreadsheet key, original archive, curated Code list | `spreadsheet_upload_policy_test.rb` |
| Valid CSV/XLSX, legacy task XLS, chat exclusions | spreadsheet + safe attachment policy tests |
| Renamed, empty, exact-size, malformed, active, external and traversal payloads | spreadsheet + safe attachment policy tests; existing DOCX helper tests |
| Safe names, byte-preserving DOCX, converted images, old attachment types | `batch03_docx_attachment_test.rb`, `comment_test.rb` |
| Cross-project denial, group authorization, deletion | safe attachment tests, existing `comment_test.rb` / `upload_security_test.rb` |
| Retry idempotency, failure before/after storage, cleanup | existing `batch03_docx_attachment_test.rb` |
| Safe INFO rejection and truthful success logging | safe attachment tests and `file_helper_test.rb` |
| Task submissions: authorization, MIME, archive bounds, duplicates | `upload_security_test.rb` |
| Requirements, picker/drop/paste, confirmation, draft preservation, proxy 413 | companion doubtfire-web PR tests |
| Direct/proxied 29,999,999 and 30,000,000 byte uploads | doubtfire-deploy `production/tests/probe_upload_limits.py` |

The proxy stays finite and larger than the application limit plus multipart
headers. The existing deploy default is 1g; the deploy PR validates a minimum
32m and provides JSON 413 responses. It does not increase the application limit.
See [deploy PR 37](https://github.com/ontrack-features-t2-2026/doubtfire-deploy/pull/37)
and [safe logging PR 167](https://github.com/ontrack-features-t2-2026/doubtfire-api/pull/167).

Known security follow-ups from FILE-S01 (aggregate storage quotas, simultaneous
submission race coverage, abandoned worker cleanup) are not claimed resolved by
attachment-format support. The existing per-file and archive limits remain.
Review and merge are intentionally left to another reviewer.
