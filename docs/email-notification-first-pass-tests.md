# Email Notification – First Pass Test Cases

## Purpose

The purpose of this document is to define an initial set of test cases for user email notification preferences and correct email delivery before implementation begins.

This task documents expected behaviour only. No production code has been modified.

## Test Cases

| Test ID | Scenario | Preconditions | Test Action | Expected Result |
|---|---|---|---|---|
| EN-01 | Notifications enabled | The user has enabled email notifications and has a valid email address | Trigger a valid notification event | Exactly one email is delivered to the intended recipient |
| EN-02 | Notifications disabled | The user has disabled email notifications | Trigger the same notification event | No email is created, queued, or delivered |
| EN-03 | Wrong recipient | The event belongs to User A, while User B also exists in the system | Trigger the notification for User A | Only User A receives the email; User B receives nothing |
| EN-04 | Duplicate event | The same notification event is processed twice | Process the duplicate event | Only one email is delivered |
| EN-05 | Changed preference | The user changes the preference from enabled to disabled before the event | Trigger a notification after the preference change | The updated preference is respected and no email is delivered |

## Key Finding

Correct email delivery depends on validating both the user's latest notification preference and the intended recipient before sending the email.

## Recommended Next Step

Confirm how duplicate notification events will be identified and determine where automated tests for these scenarios should be implemented when the feature is developed.

## Current Blocker

The email notification feature is not yet fully implemented, so these test cases define expected behaviour only and cannot yet be executed as automated tests.