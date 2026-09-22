# The effective resubmission deadline

**Status: the rule written here is the rule OnTrack already ran, written down. It is
not approved policy. SLR-E01 (Confirm the Intended Post-Feedback Deadline Rule) has
to confirm or correct it.**

When staff send a task back to a student for more work, the student needs time to do
that work. If the deadline is close, OnTrack quietly moves it. Nobody had written down
what "close" means or how much time gets added, so SLR-E02 wrote it down and fixed the
parts that were wrong no matter which policy SLR-E01 lands on.

## The rule as it stands

A task earns one resubmission extension when all of these are true.

| Condition | Where it lives |
|---|---|
| The task was set to Fix and Resubmit, Discuss, Rediscuss or Demonstrate | `Task#resubmission_extension_statuses` |
| The deadline is less than 7 days away, measured from the assessment | `Task#resubmission_extension_window` |
| The unit grants more than 0 weeks on resubmit | `Task#resubmission_extension_weeks` |
| The task can still be extended without passing the unit deadline | `Task#can_apply_for_extension?` |
| This round of feedback has not already had one | `Task#resubmission_extension_comment` |

Two supporting values decide *when* those conditions are read.

| Value | Where it lives |
|---|---|
| The moment the deadline passes, end of its day anywhere on earth | `Task#effective_deadline` |
| The far edge of the window, 7 days after the assessment | `Task#resubmission_extension_window_end` |

The extension is the unit's `extension_weeks_on_resubmit_request`, capped so it never
runs past the unit deadline. Units that let students manage their own dates
(`allow_flexible_dates`) never get one.

A round of feedback starts when the student submits. So a student who resubmits and is
sent back again earns another extension, and staff who assess the same submission twice
do not move the deadline twice.

## What SLR-E01 has to decide

1. Is 7 days the right window, and should it be measured from the assessment or from
   the student reading the feedback.
2. Are those four statuses the right list. Demonstrate and Discuss ask the student to
   turn up, not to resubmit, so they may not belong.
3. Is one extension per submission right, or should it be one per task for the whole
   trimester.
4. Whether anything should be applied retroactively. Nothing here is. Tasks that were
   over-extended by the old behaviour keep the weeks they were given.
5. Whose day a deadline belongs to. This branch says the student's, read off their campus,
   because a deadline day that is not the student's day is not a deadline anyone can act
   on. On an install that has left `campuses.timezone` empty nothing changes at all. On one
   that has filled it in, a task near midnight can now fall on a different day than it did,
   which means a small number of students qualify who did not, and the other way round.

Changing 1, 2, 3 or 5 is a change to one of the methods named in the tables above.

**Card requirement 1 is still open.** It asks the rule to conform to the approved policy,
and there is no approved policy: SLR-E01 has not started. Writing one here would be
inventing it. What this branch does instead is write down the rule OnTrack already ran and
put each part of it in one named place, so that confirming or correcting it later is a
small edit rather than an archaeology exercise.

## Worked examples, all covered by tests in `test/models/task_test.rb`

| Case | Result |
|---|---|
| Task due in 2 days, set to Fix and Resubmit | 1 week added, deadline moves once |
| Same task assessed again, same submission | Nothing changes |
| Same task set to Discuss straight after | Nothing changes |
| Student resubmits a week later, sent back again | A second week added |
| Tutor grants 2 more weeks, then reassesses | Stays at 3 weeks, nothing added or removed |
| Task due in 4 weeks, set to Fix and Resubmit | No extension |
| Unit grants 0 weeks on resubmit | No extension |
| Assessment processed with a date from 3 weeks ago | No extension, the window was shut then |
| A prerequisite fix cascades to a dependent task, twice | The dependent task gets 1 week, not 2 |
| Melbourne task due 10:30, either side of a clock change | Due at the end of the day it was set for, both times |
| Seven days from 09:00, the week the clocks move | Ends at 09:00, 167 real hours one way and 169 the other |
| Due Mon 5 Oct 2026, sent back Thu 1 Oct, clocks forward on the Sunday | Due Mon 12 Oct, not Sun the 11th |
| A student asks for a week, then is sent back near the deadline | Two separate extensions, only the second is a resubmission one |

## Why the deadline used to move more than once

`Task#grant_extension` adds weeks, it does not set them. The old code ran the whole check
on every call to `Task#assess`, so a second Fix and Resubmit on the same submission added
another week, and so did the recursive fix that cascades to dependent tasks. An already
overdue task was the worst case, because it stays inside the 7 day window after being
extended, so it could be extended again and again.

## What the fix does

- One extension per round of feedback. The check is an `ExtensionComment` recorded against
  the task, so it survives restarts, retries and duplicate events, and needed no migration.
- That comment is also the audit trail. It records the weeks, the status that triggered it,
  who assessed it, when, and a sentence the student can read. `task_status_id` is set on the
  ones OnTrack worked out and nil on ones a student asked for, which is what tells them
  apart. `ExtensionComment#serialize` exposes `resubmission_extension` and `source_status`
  for the interface and for notifications.
- **Not `automatic`.** That word was already taken. `ExtensionComment#assess_extension` uses
  it for a request a student made that the unit approved without a person weighing it up,
  which is a different thing entirely - it is about who signed the extension off, not about
  where it came from. One word carrying two meanings inside one class is how the wrong
  branch gets taken, so the predicate is `resubmission_extension?` and the parameter on
  `assess_extension` is `auto_approved`. Nothing in the class says "automatic" any more.
- The window is measured from the assessment's own timestamp rather than the wall clock,
  so replaying an event gives the answer it gave at the time, and the seven days are added
  as a duration rather than 168 fixed hours.
- The whole calculation is now done in the student's own time zone, which is the fix for
  the date drift described in the next section.

## Which day a deadline falls on

This is the part that was wrong, and it was wrong in two ways at once.

A deadline in OnTrack is a day, not an instant. A task due on Monday is not late until
Monday is over, and OnTrack is generous about that: it treats the deadline as the end of
that day *anywhere on earth*, which is 23:59:59 at UTC-12. So the one thing the code has
to get right is which day it is talking about.

It got that day by reading the year, month and day straight off the deadline as the
database handed it back. That reads them in whatever `Time.zone` is, and **nothing in
`config/` sets `config.time_zone`, so `Time.zone` is UTC**. Meanwhile every campus carries
its own `timezone` column, added in `20251016033638_add_timezone_to_campuses`, and nothing
in this calculation read it.

That is not just an offset. A campus in Melbourne is +11:00 through summer and +10:00
through winter, so the same wall clock deadline sits on one UTC day for half the year and
the next one for the other half. A task due at 10:30 on Thursday 2 April 2026 was treated
as due on Wednesday the 1st. The identical task a week later, on Thursday 9 April, was
treated as due on Thursday the 9th, because the clocks had gone back on the Sunday in
between. Two deadlines set a week apart came out eight days apart. The seven day window
had the matching problem in the other direction, landing an hour late in the week the
clocks go forward and an hour early in the week they go back.

The fix is that the calculation now names its own zone instead of inheriting one.

| Method | What it does now |
|---|---|
| `Task#deadline_time_zone` | The campus's `timezone`, falling back to the application zone |
| `Task#deadline_date` | Reads a deadline's calendar day in that zone |
| `Task#to_same_day_anywhere_on_earth` | Builds the end of that day at a fixed `-12:00` |
| `Task#resubmission_extension_window_end` | Adds seven days in that zone, so it keeps its wall clock |

`Campus#timezone` already falls back to the application zone when the column is empty, and
a project with no campus falls back to the same place. **So on an install that has not
filled in campus time zones, every one of these produces exactly the value it produced
before.** On an install that has filled them in, the deadline is now the student's day.

`Task#raw_extension_date` and `Task#max_date_with_spec_con_days` were fixed at the same
time and for the same reason. They are what turn extension weeks into a date, so leaving
them reading the day in UTC would have put the corrected deadline back onto the wrong day
as soon as a task was extended.

Three tests in `test/models/task_test.rb` cover this, all of them on a real Australian
campus and none of them touching the application zone. Reverted against the old
calculation they fail by a day on the deadline and by an hour on the window.

**`config.time_zone` is deliberately still unset.** Setting it is a one line change with a
blast radius across every date in the product, and this branch targets `11.0.x`, which is a
release branch. It is named as a follow-up below rather than done here.

## Known gaps, not fixed here

Group submissions copy the submitter's extension count onto each member task and then run
the check on each of them, so a group can end up further ahead than its submitter. That is
a separate defect in `GroupSubmission#propagate_transition` and it needs its own ticket.

These came out of an independent review of the change. None of them is a regression, every
one of them is either older than this branch or a consequence of deliberately not making a
retroactive change, and each needs a decision from SLR-E01 rather than a quiet fix.

### SLR-E02-F1: set `config.time_zone`, or decide not to

Nothing in `config/` sets `config.time_zone`, so the application zone is UTC everywhere.
The deadline calculation no longer cares, because it names the campus zone itself. It is
the only thing in the product that does.

That is the follow-up. Every other date OnTrack renders, sorts, groups or writes to a
webcal is still read in UTC, including on a Melbourne campus that is ten or eleven hours
ahead of it, and a fair number of those will be a day out on the screen for exactly the
reason the deadline was.
Setting `config.time_zone` is one line, and one line with a blast radius across the whole
product, so it does not belong on `11.0.x` next to a deadline fix. **It is not done here on
purpose.** It needs its own ticket, its own read of what breaks, and a call on whether a
single application zone is even the right answer for a product with campuses on different
ones.

### SLR-E02-F2: tasks extended by the old code carry no marker

The guard asks whether this round of feedback already has an `ExtensionComment` recording a
resubmission extension. The old code created none, so a task that was already extended by
the old behaviour looks untouched. The first time the same submission is assessed after this
lands, it can be extended one more time. From then on it is idempotent like everything else.

So the exposure is **one extra week, once, per affected task** - and only where the task was
already extended by the old code, is reassessed before the student submits again, and is
still inside the seven day window. The unbounded case, where an overdue task could be
extended on every single pass, is closed by this branch regardless.

Three ways to close the rest were considered and none of them is safe to do here.

| Option | Why not |
|---|---|
| Backfill comments for the old extensions | Nobody recorded which extensions were automatic or what triggered them, so this writes an audit trail that was never true, into every affected student's comment thread |
| Treat "extension weeks no comment accounts for" as already spent | `GroupSubmission#propagate_transition` copies the submitter's extension count onto every member task without a comment, so this would silently deny group members their first legitimate extension |
| Stamp a one-off marker in a migration | Needs a `task_status_id` the migration cannot know, and a student-visible comment on every affected task |

**So this is a data migration decision, not a code one, and it needs the retroactivity call
from SLR-E01 first.** Requirement 6 of the card rules out retroactive changes, and every
option above is one. Named here so it is picked up deliberately rather than discovered.

**Nothing serialises the check.** The read of the guard, the `extensions` update and the
comment insert are three statements with no lock and no transaction around them. Two
assessments landing together can both see no comment and both grant. A row lock on the task
would close it and is the obvious follow-up.

**The extension is written before the comment.** `grant_extension` persists first and
`record_resubmission_extension` saves after. If the comment raises, the deadline has already
moved and no key exists to stop the next assessment moving it again. Wrapping the pair in a
transaction is the fix and it belongs with the lock above.

**Group threads show one comment per member.** The comment is recorded against each member
task, and `Task#all_comments` returns every comment across the group submission, so a
three-person group assessed once shows three resubmission extension comments to everyone. The
extensions themselves are per task and correct. Only the thread is noisy.

**Second-precision timestamps.** The guard compares `date_extension_assessed` against
`submission_date`. On a database still using the older second-precision `datetime` columns,
an assessment and a genuine resubmission inside the same second compare equal and the new
round is suppressed. Unlikely by hand, reachable by a script.
