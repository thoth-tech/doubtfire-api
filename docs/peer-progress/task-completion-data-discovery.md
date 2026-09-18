# PPI — Locate existing task-completion data in the API

**Original ticket:** PPI - Locate existing task-completion data in the API (Discovery, starter task)
**Author:** Gaurav Manohar Myana
**Repo checked at the time:** `doubtfire-api`, branch `feature/peer-progress-indicator`

> Preserved here, unedited from the original ticket deliverable, per PPI-D02's requirement to keep a
> link to the prior discovery work. See [data-source-map.md](./data-source-map.md) for how this
> compares against the actual PPI-B01 implementation found on `ppi/student-progress-endpoint`.

## Purpose

Find what task-completion data already exists in the API, so the Peer Progress Indicator isn't
designed around information that isn't actually available.

## Relevant Rails models

| Model | File | Relevant fields/notes |
|---|---|---|
| `Task` | `app/models/task.rb` | `task_status_id`, `completion_date`, `target_start_date`, `submission_date` |
| `TaskStatus` | `app/models/task_status.rb` | 15 fixed statuses (complete, working_on_it, fail, etc.) |
| `Project` (student's enrolment in a unit) | `app/models/project.rb` | `task_stats` (JSON): `{ red_pct, orange_pct, green_pct, blue_pct, grey_pct, order_scale }` — one student's own task-status mix |
| `Unit` | `app/models/unit.rb` | `#student_task_completion_stats` — cohort-wide median/min/max/quartile of completed tasks, broken down by tutorial and grade |

## Relevant API endpoints

| Endpoint | Access | Returns |
|---|---|---|
| `GET /projects/:id` | Authenticated user | Individual `task_stats` — **but hidden from the student themselves** (`unless: :for_student` in `ProjectEntity`) |
| `GET /units/:id/stats/task_completion_stats` | Staff only (`:download_stats`) | Cohort-wide completed-task stats (median/min/max/quartiles) by unit/tutorial/grade |
| `GET /units/:id/stats/task_completion_snapshots` | Staff only (`:download_stats`) | Historical point-in-time snapshots of status counts |

## Data gap

**No student-facing endpoint exposes any peer/cohort completion data**, and a student can't even see
their own `task_stats`. Confirmed in two places:

1. `Unit.permissions` grants students only `[:get_unit]` — `:download_stats` is staff-only.
2. `ProjectEntity` explicitly excludes `task_stats` when the viewer is the student themselves.

## Key finding

The aggregation the PPI needs — anonymized cohort completed-task stats (median/quartiles by
tutorial/grade) — **already exists** in `Unit#student_task_completion_stats`. It does not need to be
built. It's just not reachable by students.

## Recommended next step

Add a new, student-authorised endpoint (e.g. `GET /units/:id/my_progress`) that returns the calling
student's own `task_stats` plus the cohort aggregate for their tutorial/grade, by reusing
`Unit#student_task_completion_stats` — without granting students the broader `:download_stats`
permission.

## Blockers

None. Scope was read-only exploration of the existing codebase; no production code changed.

## What actually happened next (added retrospectively for PPI-D02)

The recommendation above (reuse `Unit#student_task_completion_stats`) was **not** what PPI-B01 built.
See [data-source-map.md](./data-source-map.md) §1 "Divergence from the original discovery task" for
what was actually implemented instead, and why.
