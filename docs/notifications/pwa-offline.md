# PWA offline behaviour

This document records what users experience when OnTrack loses network
connectivity and explains the relevant Angular service-worker configuration.

No caching configuration or application behaviour was changed as part of this
documentation-only investigation.

## Configuration under test

Testing used the generated static development build from the
`doubtfire-web/feature/notifications` branch.

Before the final offline tests, the environment confirmed that:

- `navigator.serviceWorker.controller` referenced `ngsw-worker.js`.
- `/ngsw/state` reported `Driver state: NORMAL ((nominal))`.
- `/index.html` existed in the versioned `app` asset cache.
- **Bypass for network** was disabled.
- **Update on reload** was disabled.
- Ordinary reloads were used rather than forced or hard refreshes.

The generated static build was used for the final test so the service worker
could install and cache the built application files consistently.

## What is cached

### Application shell

The `app` asset group uses `installMode: "prefetch"` and includes:

- `/index.html`
- the compiled JavaScript bundles
- the compiled CSS bundles
- the favicon
- the web application manifest

These resources are downloaded when the service-worker application version is
installed.

The `assets` asset group uses `installMode: "lazy"`. Matching images, fonts,
and other assets are cached after they are requested rather than all being
downloaded during installation.

### Navigation URLs

The service-worker configuration contains these navigation rules:

```json
[
  "/**",
  "!/**/*.*",
  "!/**/*__*",
  "!/**/*__*/**",
  "!/JPlag/**",
  "!/JPlag",
  "!/sidekiq/**",
  "!/sidekiq",
  "!/beta/**",
  "!/beta",
  "!/legacy",
  "!/legacy/**"
]
```

A URL must match a positive rule and must not match any negative rule to be
treated as an Angular navigation request.

The `!/**/*.*` rule is intended to exclude file URLs whose final path segment
contains a file extension. However, it also excludes valid OnTrack task routes
when the task abbreviation contains a period.

For example:

- `/` is treated as a navigation request.
- `/projects/2/dashboard` is treated as a navigation request.
- `/projects/28/dashboard/A15` is treated as a navigation request.
- `/projects/2/dashboard/2.2P` is not treated as a navigation request because
  its final path segment contains a period.

No `navigationRequestStrategy` override is configured. Angular therefore uses
its default `performance` navigation strategy for matching navigation
requests. This strategy serves the configured `/index.html`, which is normally
available from the application cache.

An excluded URL is not redirected to the cached index file. When the network
is unavailable, the excluded request cannot be completed and may produce the
browser's native error page.

### API data

The `api` data group uses the following policy:

```json
{
  "name": "api",
  "urls": ["/api"],
  "cacheConfig": {
    "maxSize": 0,
    "maxAge": "0u",
    "strategy": "freshness"
  }
}
```

`freshness` is a network-first strategy. The zero maximum size and zero maximum
age indicate that matching responses are not intended to provide a reusable
offline API cache.

Users should therefore not rely on grades, task state, submission details,
comments, prerequisites, or other API-backed information being available
after connectivity is lost.

This configuration should not be described as proof that an API response can
never be written to or returned from a service-worker cache under any
condition. Its practical effect and intent are that API data should not be
relied upon for meaningful offline reuse.

A successful response status such as `200` or `304` does not, by itself,
identify where the response came from. The Network panel's **Size**,
**Transferred**, and **Initiator** information must be inspected before
identifying a response as coming from the service worker, memory cache, disk
cache, or network.

## Observed offline behaviour

### Included navigation route

An ordinary offline reload of `/` loaded the cached Angular application shell
rather than Chrome's native `HTTP ERROR 504` page.

Static resources such as the favicon and application icon were returned by the
service worker. Authentication, API, analytics, and other uncached requests
failed while the browser was offline.

The application shell could therefore load, but API-backed application state
was unavailable or incomplete. This confirms that caching the shell does not
provide a complete offline mode.

### Dotted task route

An ordinary offline reload of:

```text
/projects/2/dashboard/2.2P
```

produced Chrome's native `HTTP ERROR 504` page.

Before this test:

- `ngsw-worker.js` controlled the page.
- The service-worker driver state was normal.
- `/index.html` existed in the application cache.
- The reload was an ordinary reload rather than a forced refresh.

The route was excluded from Angular navigation handling because its final
segment, `2.2P`, contains a period and matches the `!/**/*.*` negative rule.

The service worker therefore did not use cached `/index.html` as the
navigation fallback. With the network unavailable, the route request failed
and Chrome displayed its native error page.

This is a route-specific navigation limitation. It is not evidence that the
application shell was missing from the service-worker cache.

### Losing connectivity mid-session

When connectivity was removed without reloading, the already-loaded
application shell and information held in memory remained visible.

Requests for new API-backed information failed. This included secondary task
requests such as prerequisite, submission-detail, and comment requests when
the information had not already been loaded.

One observed failure produced this toast:

> Failed to fetch prerequisites for task definition: TypeError: Cannot read
> properties of null (reading 'error')

This is a technical error rather than a clear explanation that the application
has lost network connectivity.

Some previously requested resources may still return successful statuses while
offline. Their source must be confirmed using the Network panel rather than
being inferred from the status code alone.

## Summary

OnTrack caches its Angular application shell, but offline reload behaviour is
route-dependent.

Routes that satisfy the configured navigation rules can receive cached
`/index.html`. Valid task routes whose final path segment contains a period are
excluded by `!/**/*.*` and can produce a browser-level `504` when reloaded
offline.

Even when the shell loads, API-backed information cannot be relied upon
offline. Losing connectivity can therefore leave the application shell visible
while new data requests fail and technical errors are displayed.

The current behaviour can result in three different user experiences:

1. An included navigation route loads the cached application shell, but
   API-backed information is missing or fails.
2. A dotted task route produces Chrome's native `504` page because it is
   excluded from navigation fallback.
3. Losing connectivity during an existing session leaves the shell visible
   but can produce failed requests and technical error messages.

## Recommendation

A separate `doubtfire-web` ticket should investigate narrowing or replacing
the `!/**/*.*` navigation exclusion so valid task abbreviations containing
periods can use the Angular navigation fallback without treating genuine
static-file requests as application routes.

A separate ticket should also consider:

- displaying an offline or disconnected status;
- replacing technical request errors with user-friendly messages;
- safely handling absent network responses;
- providing a retry path after connectivity returns; and
- identifying which information, if any, should be available offline.

These changes are outside the scope of this documentation-only ticket.

## How to verify manually

1. Build and serve the generated Angular output.
2. Load OnTrack while online.
3. Wait until the service worker is ready.
4. Confirm that
   `navigator.serviceWorker.controller?.scriptURL`
   ends in `ngsw-worker.js`.
5. Confirm that `/ngsw/state` reports
   `Driver state: NORMAL ((nominal))`.
6. Confirm that `/index.html` exists in the versioned `app` asset cache.
7. Ensure **Bypass for network** is disabled.
8. Ensure **Update on reload** is disabled.
9. Load `/` while online.
10. Set Network throttling to **Offline**.
11. Use ordinary Command+R and confirm that the cached Angular shell loads.
12. Do not use Shift+Command+R or **Empty cache and hard reload**.
13. Return Network throttling to **No throttling**.
14. Load `/projects/2/dashboard/2.2P`.
15. Set Network throttling back to **Offline**.
16. Use ordinary Command+R.
17. Confirm that the dotted task route produces Chrome's native `504` page.
18. Return online and load a task.
19. Remove connectivity without reloading.
20. Navigate to information that has not already been requested.
21. Record the failed API requests and any user-facing error.
22. Use the Network panel's **Size**, **Transferred**, and **Initiator**
    information before attributing successful responses to a particular cache.

## Relevant configuration

The behaviour described here is controlled primarily by:

- `doubtfire-web/ngsw-config.json`
- the generated `ngsw.json` service-worker manifest
- Angular's service-worker navigation request handling
- the application's handling of failed API requests
