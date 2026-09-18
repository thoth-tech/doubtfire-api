# Optional collection pagination

Existing callers still receive a complete JSON array when neither `page` nor
`per_page` is provided. No web or mobile client update is required to retain
the existing behaviour.

The following GET endpoints support opt-in pagination:

- `/api/activity_types`
- `/api/campuses`
- `/api/users`, `/api/users/convenors`, `/api/users/tutors`
- `/api/units`
- `/api/projects`
- `/api/units/:unit_id/group_sets/:group_set_id/groups/:group_id/members`

Provide either `page` or `per_page` to opt in. The missing parameter defaults
to page 1 or 50 records per page. Both parameters must be positive scalar
integers; the maximum page is 2,147,483,647 and maximum page size is 500.
Malformed, blank, zero, negative and out-of-range values return HTTP 400.

Paged responses remain JSON arrays, ordered by record ID. Existing filters,
preloads and access permissions apply before pagination. Pages past the end
return an empty array. These response headers describe the authorised result:

- `X-Total-Count`: total matching records before pagination
- `X-Page`: requested page
- `X-Per-Page`: effective page size
- `X-Total-Pages`: number of pages (zero for an empty collection)

These headers are exposed through CORS for browser clients. For example,
`GET /api/projects?page=2&per_page=25&include_inactive=true` returns the second
page of the signed-in user's enrolled projects, including inactive units.

ID ordering makes pages deterministic for an unchanged collection. This is
offset pagination, not a snapshot: concurrent additions or deletions may
change page boundaries. Clients needing the full current list can retain the
existing unpaged request, or refresh their pages.
