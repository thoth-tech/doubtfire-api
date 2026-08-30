# EN-S04 – Recipient and Email Amplification Risk Review

## Purpose

This review looks at the recipient and email amplification risks for notification events EN-V01 to EN-V08.

The main question for each event is:

- Who should actually receive the notification?

- Can one user action cause several internal updates?

- If it can, how many emails could that generate?

- Is there already a guard in place?

- If not, what kind of guard should be added when the event is implemented?

This is a review task only. No production notification code was changed as part of EN-S04.

The review was completed against the current `feature/notifications` branch of `doubtfire-api`.

---
## Main amplification risks found

While reviewing the notification paths, I found three places where one logical action can result in several internal operations.

### 1. Unit date changes

`Unit#propogate_date_changes_to_tasks` runs when a unit start date changes.

It loops through the unit's task definitions and calls:

`td.propogate_date_changes date_diff`

`TaskDefinition#propogate_date_changes` then changes the task dates and saves the TaskDefinition.

This means one unit date change can save many TaskDefinitions.

If a due-date email was attached directly to a general TaskDefinition update callback, one unit-level change could accidentally generate emails for every affected task and every eligible student.

If there are `T` task definitions and `S` eligible students, the worst-case fan-out could be approximately:

`T × S emails`

The current EN-V01 implementation avoids this by raising the event from the normal task-definition update API rather than from a generic model callback.

---
### 2. Moving a group between tutorials

`Group#switch_to_tutorial` processes every project in the group.

For each project it temporarily calls:

`remove_member(proj, notify: false)`

and later:

`add_member(proj, notify: false)`

These membership changes are internal steps needed to move the group. They are not real group leave/join events.

Without the `notify: false` guard, a group with `N` members could receive:

`N removal emails + N addition emails`

or:

`2N false emails`

from one tutorial move.

The current implementation correctly suppresses these temporary notifications.

---
### 3. Group task transitions

`Task#create_submission_and_trigger_state_change` loops across every task in a group submission. For the original task, `Task#trigger_transition` can also call `GroupSubmission#propagate_transition`, which calls `trigger_transition(... group_transition: true ...)` for every other task.

For `N` member tasks, a notification attached blindly to every transition invocation could therefore see up to:

`1 + (N - 1) + (N - 1) = 2N - 1 transition invocations`

The first term is the original task, the second is the propagation pass, and the third is the remaining calls from the outer group-task loop. Only `N` member tasks exist, and some repeated calls may be no-ops, but a new event still needs both an actual-status-change check and an original-action guard.

The existing `group_transition` flag can distinguish the original action from propagated or internal calls. Raising a group-submission notification once at the group boundary is safer still.

---

# EN-V01 – Task due date changed

## Trigger

The current implementation raises this event from:

`app/api/task_definitions_api.rb`

After the normal task-definition update, the API checks whether `due_date` actually changed and queues:

`TaskDueDateChangedNotificationJob`

The notification is deliberately not attached to every TaskDefinition save.

## Recipient

The intended recipients are eligible students affected by that task.

The current job filters based on the active unit, enrolment and target grade. The existing task-notification preference is then handled through the notification system.

## Worst case

For one directly changed task and `S` eligible students:

`S emails`

This is expected because the change affects the cohort.

The more dangerous case would be a unit date change affecting `T` tasks, which could become:

`T × S emails`

if the notification was attached to every TaskDefinition save.

## Existing guard

The current API-level trigger avoids that cascade.

The job also checks that the queued due date is still current, which helps avoid stale notifications if the date changes again before the job runs.

## Recommendation

Keep this event attached to the normal task-definition update workflow.

Do not move it to a generic TaskDefinition lifecycle callback.

If students need to be notified about a bulk unit schedule change in the future, a separate unit-level notification or digest would be safer than one email for every changed task.

---
# EN-V02 – New task available

## Trigger

The implementation queues:

`NewTaskAvailableNotificationJob`

after a `TaskDefinition` is successfully created through the normal API, CSV
task import or unit rollover/copy workflow. Bulk workflows enqueue only after
the task definition is fully populated.

A generic `TaskDefinition after_create` callback is not used.

## Recipient

The intended recipients are students for whom the new task is actually available.

The current job checks things such as:

- active unit;

- current enrolment;

- target-grade eligibility;

- effective task start date; and

- task notification preference.

## Worst case

For one new task and `S` eligible students:

`S emails`

This is expected.

If a bulk operation creates `T` tasks, the fan-out can become:

`T × S emails`

from one import. This is intentional when all `T` rows are new tasks, but it is
kept off the request thread and updated rows are excluded.

## Existing guard

The implementation uses explicit post-workflow triggers rather than a generic
model callback. The API, import and rollover requests only queue Sidekiq jobs;
they do not deliver cohort email inline.

It reserves an immutable task-definition key for the student under a unique
database index. This protects against concurrent fan-outs, retries, task
renames and the scheduled future-date check without confusing a genuinely new
definition that reuses an abbreviation.

## Recommendation

Keep each workflow trigger explicit and best-effort.

Do not replace it with a generic `after_create` callback.

Keep bulk fan-out in Sidekiq, enqueue only genuinely new imported/copied tasks,
and retain the effective-date and duplicate guards.

---
# EN-V03 – Task due soon

## Trigger

There is no model update that naturally happens when a deadline becomes close, so EN-V03 uses:

`SendDueSoonRemindersJob`

The job is scheduled through `config/schedule.yml`.

## Recipient

The job considers students with outstanding eligible tasks whose actual due date falls within the reminder window.

It uses the existing due-date calculation rather than simply reading the raw TaskDefinition date.

## Worst case

A scheduled run can legitimately find many student/task combinations.

If `S` students each have `T` eligible outstanding tasks inside the reminder window, the theoretical fan-out can approach:

`S × T reminders`

This is expected scheduled workload rather than amplification from a single convenor action.

## Existing guard

Before sending, the job checks whether that student/task already has a `task_due_soon` notification.

The intended behaviour is therefore:

`one reminder per student per task`

Running the job again should not send the same reminder again.

## Recommendation

Keep the duplicate check.

The schedule should not be made unnecessarily frequent because each newly matched student/task pair can result in an email.

The schedule entry should also not be described as fully verified in development until the required Sidekiq worker is available.

---
# EN-V04 – Tutorial changed

## Proposed trigger

The relevant method is `Project#enrol_in`.

A matching enrolment in the requested tutorial is a no-op. A newly created row, however, does not always mean a first-time enrolment. When a project has more than one tutorial enrolment and is moved to a tutorial without a stream, `Project#enrol_in` destroys the existing enrolments, sets the local enrolment to `nil`, and creates a replacement row.

For that reason, EN-V04 must compare the project's effective tutorial IDs before and after the operation. It must not use `tutorial_enrolment.nil?` by itself to decide that this is a first-time enrolment.

## Recipient

The correct recipient is `project.student`.

Only the student whose effective tutorial membership changed should receive the notification. The whole old tutorial or new tutorial must not be used as the recipient list.

## Worst case

A normal one-student move should generate `1 email`.

A real group tutorial move involving `N` students can legitimately generate `N tutorial-change emails`, one for each student whose effective tutorial membership changed.

## Risk

The main recipient risk is notifying everyone in the old or new tutorial rather than only the affected students.

There is also a state-detection risk: the multiple-enrolment consolidation path creates a replacement row even though it represents a genuine tutorial move.

## Recommendation

Capture the project's tutorial IDs before and after `Project#enrol_in`, and raise EN-V04 only when there was at least one prior tutorial enrolment and the effective tutorial set genuinely changed.

Do not notify for:

- a genuine first enrolment;
- selecting the same tutorial again; or
- internal cleanup that leaves the effective tutorial membership unchanged.

Keep the recipient as the affected project's student. Review bulk and import callers separately before allowing them to generate student emails.

---

# EN-V05 – Group membership changed

## Trigger

The current implementation uses:

`Group#add_member`

and:

`Group#remove_member`

## Recipient

The current scope is student-only.

The recipient is the student whose membership changed.

Other members of the group are not notified.

## Worst case

A normal direct addition should generate:

`1 email`

A normal direct removal should generate:

`1 email`

The important amplification case is `Group#switch_to_tutorial`.

Without a guard, a group with `N` members could receive:

`2N false group membership emails`

because every student is temporarily removed and added again.

## Existing guard

The current tutorial-switch path calls both membership methods with:

`notify: false`

This correctly prevents the internal remove/add operations from becoming real notification events.

The current implementation also avoids broadcasting the event to every member of the group.

## Stale member risk

The notification uses the project involved in the current add/remove operation rather than walking old GroupMembership records.

This reduces the risk of former or inactive members receiving a notification about a later membership change.

## Recommendation

Keep the existing `notify: false` guard for internal operations.

The event should continue to notify only the student whose membership changed unless the team explicitly decides that group-wide notifications are required.

Bulk membership changes should also remain explicitly controlled rather than inheriting notification behaviour automatically.

---
# EN-V06 – Student submitted for marking

## Proposed trigger

This event overlaps with `Task#trigger_transition` because a student submission moves a task into a ready-for-marking or feedback state.

EN-E02 already uses this transition area for task status notifications, so EN-V06 must not add another notification call blindly without checking the existing behaviour.

## Recipient

The intended recipient is the authorised tutor returned by `project.tutor_for(task_definition)`.

The implementation must safely handle a missing recipient. Before implementation, the team should also record whether a cross-tutorial group has one responsible tutor or should notify each distinct authorised tutor. It must not silently assume that every member project resolves to the same tutor.

## Amplification risk

Group submissions are the important case.

`Task#create_submission_and_trigger_state_change` loops across all `N` member tasks. The original task's `Task#trigger_transition` can also call `GroupSubmission#propagate_transition`, which calls `trigger_transition(... group_transition: true ...)` for the other `N - 1` tasks.

A notification attached to every transition invocation could therefore see up to:

`2N - 1 transition invocations`

This consists of the original call, `N - 1` propagation calls, and `N - 1` remaining calls from the outer group-task loop. Only `N` member tasks exist and some repeated calls may be no-ops, but an event sent without an actual-status-change guard could still duplicate.

## Recommendation

The cleanest option is to raise EN-V06 once from the group-submission boundary rather than once from every member task.

If the notification remains inside `Task#trigger_transition`, require all of the following:

- the task genuinely changed into the submitted or ready-for-feedback state;
- the call represents the original action, with `group_transition: false`; and
- duplicate protection prevents the same logical submission from notifying the same authorised tutor twice.

Record the lead-approved tutor rule for cross-tutorial groups. A tutor receiving many independent submissions is a separate volume concern and may support a later digest, but it is not the same as duplicate amplification.

---

# EN-V07 – Portfolio submission received

## Proposed trigger

The portfolio submission path writes:

`project.portfolio_submission_date = Time.zone.now`

in:

`app/api/projects_api.rb`

The reviewed branch does not currently contain a `portfolio_received` event.

## Existing portfolio emails

The existing `PortfolioEvidenceMailer` contains:

- `portfolio_ready`

- `portfolio_failed`

These describe what happened after portfolio generation.

They are different from a confirmation that the student's submission itself was received.

## Recipient

The intended recipient should be:

`project.student`

## Worst case

A normal accepted portfolio submission should generate:

`1 confirmation email`

The risk is repeated requests or retries generating multiple receipt emails for the same logical submission.

## Recommendation

Only raise the receipt notification when a genuine portfolio submission is accepted.

The implementation should prevent a retry or repeated request for the same submission from creating another receipt, while still allowing a later genuine resubmission to receive its own confirmation.

The exact deduplication mechanism should be agreed with the lead before implementation.

EN-V07 should also remain separate from the existing `portfolio_ready` and `portfolio_failed` emails because they represent different stages of the portfolio process.

---
# EN-V08 – Discussion or check-in booked

## Scope finding

This event cannot currently be implemented as written.

The reviewed API does not contain a booking model, appointment model or calendar booking table that represents a future discussion booking.

The existing discussion/check-in related models represent things that have already happened rather than a future appointment.

For example, the existing discussed-comment path records a discussion that has already taken place.

## Recipient

There is no reliable recipient or trigger to review until the event itself is redefined.

## Recommendation

Do not force EN-V08 onto an unrelated model or invent a booking concept.

The replacement event needs to be agreed with the lead first.

One possible replacement mentioned in the ticket is a notification when a discussion prompt is raised for a student, but that should only be implemented if the team agrees that this is the intended replacement.

If no replacement is agreed, closing or rescoping EN-V08 is the correct outcome.

---
# Risk Summary

| Event | Expected fan-out from one action | Main risk | Current/recommended guard |
|---|---:|---|---|
| EN-V01 – Due date changed | `S` | Unit date propagation could become `T × S` | Keep API-level trigger; avoid generic TaskDefinition callback |
| EN-V02 – New task | `S` | Bulk creation/import can become `T × S` | Queue explicit post-workflow fan-outs; exclude updated rows; retain date and duplicate guards |
| EN-V03 – Due soon | Up to `S × T` per scheduled sweep | Same reminder being sent every run | Existing duplicate check: one reminder per student/task |
| EN-V04 – Tutorial changed | `1` normally, `N` for a real group move | Whole-tutorial recipients or misclassifying the replacement-row path | Compare effective tutorial IDs before and after; notify only genuinely changed students |
| EN-V05 – Group changed | `1` normally | Tutorial switch could create `2N` false emails | Existing `notify: false` guard |
| EN-V06 – Submitted for marking | `1` intended; up to `2N - 1` transition invocations | A per-call hook can duplicate one group submission | Notify once at the group boundary, or require a real change and `group_transition: false`; record the tutor rule |
| EN-V07 – Portfolio received | `1` intended | Duplicate confirmation after retry/repeated request | Send once per genuine submission occurrence |
| EN-V08 – Discussion booked | N/A | No booking concept exists | Rescope before implementation |

---
# General recommendations

From this review, the main rule I would follow for the remaining v2 notification work is:

**A notification should represent one meaningful user-facing event, not every internal model operation needed to complete that event.**

In particular:

1. Use the project/student directly affected by the event instead of building unnecessarily broad recipient lists.

2. Avoid generic lifecycle callbacks where the same model is also changed by imports, rollovers, propagation or maintenance operations.

3. Use existing context flags such as `group_transition` when an internal update needs to be distinguished from the original action.

4. Keep bulk operations explicit. A CSV import or group-wide change should not start emailing large numbers of people simply because it happens to call the same model method as an individual action.

5. Use duplicate protection for jobs that may be retried or scheduled repeatedly.

6. Check current membership/enrolment state rather than using historical relationships when deciding recipients.

7. Where an event has no matching domain action, as with EN-V08, rescope it rather than forcing a notification onto the wrong hook.

---
# Conclusion

The review confirmed that the biggest email amplification risks are caused by internal cascades rather than by the email templates themselves.

The three clearest examples are:

- a unit date change updating many TaskDefinitions;

- a group tutorial move temporarily removing and re-adding every member; and

- a group task submission propagating the same transition across several tasks.

The current EN-V01, EN-V02, EN-V03 and EN-V05 work already contains useful safeguards against these problems.

For the remaining events, the most important protections are to keep recipients narrow, distinguish real user actions from internal propagation, and prevent repeated execution from generating duplicate email.

EN-V08 should remain unimplemented until the team agrees on a replacement event because the current API does not contain a discussion-booking concept.

Overall, the safest pattern is:

**one logical event → the intended current recipient(s) → no extra email just because the action caused several internal records to change.**
