# Stage 5 — Real Activities

Implementation branch: `feature/stage-5-activities`, based on the fetched approved `main` at `54898a3`. Stage 4 is merged (commit `718a8f1` is an ancestor), and the starting working tree was clean. Its root auth routing, session restoration, profile fetch/upsert, onboarding, editing, provider flows, and ownership checks were inspected. The six existing AuthManager tests still pass. Live provider authorization remains a separate external prerequisite; it is not inferred from compilation or an enabled button.

## Model and data flow

`Activity` remains the only activity UI/domain model. Its IDs now use UUIDs for activity, author, and category. It retains the existing card properties and adds end time, optional address, cover reference, and backend category display name. Existing mock fixtures now use stable UUIDs and remain in component previews/tests; they are not a production fallback.

`ActivityDTO` still represents the existing database row and is unchanged. `ActivityRecordDTO` decodes that same row plus relational category, a minimal organizer projection (`id, display_name`), and a filtered attendance count. It maps to `Activity`, preserving nullable fields. Unknown category slugs use the existing Other artwork while retaining the actual backend category name and UUID. Missing organizer information displays “Organizer unavailable”; attendee names/avatars are never invented. The card shows the organizer avatar when participant identities are unavailable.

`ActivityRepository` owns Supabase operations and reuses `SupabaseManager.shared.client` in production. Its methods are:

- `fetchCategories()` — real category IDs, names, and slugs; empty catalogs are an error.
- `fetchUpcomingActivities(from:categoryId:offset:limit:)` — start_at >= the requested instant, ascending start_at then id, bounded pages (default 50, maximum 100).
- `fetchActivitiesByCategory(categoryId:from:)` — reuses the same upcoming query.
- `fetchActivity(id:)` — real UUID lookup; missing/invisible rows return nil.
- `fetchActivitiesCreatedByCurrentUser(limit:)` — derives current UUID from the SDK session; includes past activities.
- `createActivity(_:)` — validates form values and derives author_id from the SDK session.
- `updateActivity(id:draft:)` — validates editable fields and filters by activity UUID and current author UUID; never sends author_id as an editable value.
- `deleteActivity(id:)` — filters by activity/current author UUID and verifies a deleted ID was returned.

All activity reads and mutation representations embed category, organizer, and `going:activity_participants(count)` filtered with `going.status=eq.going`. Left embeds retain activities with zero attending rows; interested/declined do not count. One relational query per page/detail avoids N+1 requests and fetching/truncating full participant arrays. Create/update receive their confirmed relational representation in the mutation response; no second fetch can incorrectly turn a confirmed write into a displayed failure. Empty update/delete representations are failures, not fake success.

SDK Auth errors and invalid JWT responses route back through the existing AuthManager restoration flow. Configuration, transport, validation, missing-row, ownership, and save errors have safe app messages. Tokens and raw backend errors are not displayed or logged by the new code.

## Screens and state

Feed and Explore share a small observable `ActivityListViewModel` scoped to `MainTabView`. It owns the live category selection, bounded upcoming pages, loading/empty/error states, and refresh requests. There is no new global store, auth client, caching framework, or third-party library. In-flight identical requests coalesce; category changes and successful mutations invalidate stale requests. Server-confirmed mutations immediately update/remove visible rows and trigger list refresh. Pull-to-refresh is available on both lists; “Load More Activities” exposes subsequent pages.

Feed reuses `ActivityCard` and its existing design. It offers navigation to details and Previous/Next browsing. The existing Skip/Save/Going controls are visibly disabled with coming-soon text; they do not claim persistence or attendance. Zero backend results show an empty state and Create Activity action, never mock records.

Explore reuses `ActivityRow` and partitions upcoming rows into Today, Tomorrow, This Week, and Later. Group assignment is exclusive, uses the device's calendar/time zone, and prioritizes Tomorrow across a week boundary. A minute timeline updates day grouping while the screen is visible. Feed/Explore filters share the selected real category UUID, with All Categories available. No category UUID is hardcoded in production.

`CreateActivityView` replaces the placeholder and doubles as the edit form. `ActivityFormViewModel` owns draft validation, category loading, saving, and error retention. Fields include title, backend category picker, description, native start/end date-time pickers, optional end toggle, location/address, optional numeric capacity, and category cover explanation. Only the organizer may edit, and the repository/RLS independently enforce ownership. Editing prepopulates the detail record; explicit SQL nulls clear optional fields. Busy state prevents duplicate submissions/dismissal during save. Success is shown only after the server returns the record, followed by navigation to its UUID-based detail page. Invalid/error submissions keep entered values.

`ActivityDetailsViewModel` fetches the latest activity by UUID. Details show the category cover, real title/description, local start/end date and time (including both dates for overnight activities), location/address, organizer, attendance and optional capacity. Authors see Edit and Delete; other users do not. Delete requires a confirmation alert and server success, removes the visible row, refreshes lists, and dismisses details. Missing/deleted records and read/delete failures have retry/error states.

`ActivityDraft` centralizes testable validation. Title and location must contain non-whitespace text; limits match PostgreSQL character counts (160 title, 200 location, 10,000 description). Category must exist in the loaded catalog. Optional address has a 500-character UI limit. Optional capacity must be an ASCII positive whole number within PostgreSQL integer range. Dates must be finite; end must be strictly later than start. Text is not silently trimmed or truncated. Dates remain `Date`, are encoded by the existing SDK date encoder into timestamptz-compatible values, and are displayed with native local formatting. Past starts are allowed for editing/entry but excluded from upcoming lists.

Auth, onboarding, profile data, notifications, and the DEBUG backend checker remain in place. The only AuthManager addition is a read-only UUID accessor for UI ownership checks. Profile activity-summary counts remain Stage 4 previews; no join/save/comment/calendar/photo feature was added.

## Database/RLS requirements

**No Stage 5 SQL migration is needed or added. No existing migration was modified, and no remote migration was deployed.** The existing schema already has all required fields, foreign keys, indexes, column grants and ownership policies:

- Authenticated users can read activities, categories, profiles, and participant rows in the existing shared coworker community.
- Activity INSERT requires author_id = auth.uid(). The app derives this field from its SDK session rather than editable form input.
- Activity UPDATE has both USING and WITH CHECK on author_id = auth.uid(); existing column grants forbid author reassignment.
- Activity DELETE requires author_id = auth.uid().
- RLS remains enabled; no public write policy or privileged key is introduced.

`supabase/tests/004_activity_crud.sql` adds rollback-only security checks, not a migration. It verifies own create/update/delete, other-user insert/update/delete rejection, author-ID protection, optional-field clearing, capacity/date constraints, organizer/category joins, going/interested/declined semantics, anonymous denial, retained RLS, and cascade cleanup of test attendance.

These checks and the existing 001/002/003 checks passed in isolated PostgreSQL (PGlite with minimal Supabase Auth stubs). They do not prove the remote project's deployed policies match source. Run them as postgres in a disposable test project after the existing migrations; the script rolls back all fixtures. Never rerun the initial migration against an existing database.

## Validation results

- **Debug:** simulator build and test-host compilation pass on iPhone 17 Pro / iOS 26.5.
- **Release:** simulator build passes. Device signing/archive distribution is not tested.
- **Warnings:** no new Swift warnings remain. Xcode emits its existing AppIntents metadata-extraction-skipped warning because the app does not use AppIntents.
- **Automated tests:** 25 XCTest cases pass: 6 existing auth cases, 7 domain/validation/date/mapping cases, 6 view-model cases, and 6 actual-SDK request-contract cases using URLProtocol and empty isolated test Auth storage. Tests cover empty/error/retry behavior without mock fallback, stale category responses, mutation list updates, owner checks, failed-save field retention, duplicate-submit blocking, explicit nulls, SDK author/category filters, count embeds, and rejected zero-row deletion.
- **Foundation regression:** Stage 3 configuration validation and all eight base DTO coding checks pass.
- **SQL:** existing security checks plus `004_activity_crud.sql` pass in the isolated runtime.
- **Live read:** the final Debug app launches its auth screen; the preserved DEBUG checker returned **Connected — 12 categories found** against the configured hosted project.
- **Live CRUD:** pending authenticated simulator access. The user authorized one temporary create/edit/delete test, but the inspected simulator was signed out. No activity records have been created, edited, or deleted remotely by Stage 5 validation. Live login, profile/onboarding completion, activity creation/read/display/detail/edit/delete, and cleanup remain unverified until a usable signed-in session is available. Compilation and mocked HTTP tests are not reported as live CRUD success.

Run locally (choose an installed simulator if this destination differs):

```sh
xcodebuild -project AfterWork.xcodeproj -scheme AfterWork -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' CODE_SIGNING_ALLOWED=NO test
xcodebuild -project AfterWork.xcodeproj -scheme AfterWork -configuration Release \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

### Manual live verification

1. Keep the existing public project config in the ignored `Configuration/Config.xcconfig`. Complete Google/Apple provider setup from STAGE4.md and apply the already-existing Stage 4 profile migration if it has not been deployed. Stage 5 adds no migration.
2. Launch Debug, sign in, and finish onboarding if required. Confirm Profile still displays the authenticated identity. Keep RLS enabled.
3. Open Feed and Explore. Confirm loading transitions to a real empty/result state. Pull to refresh. Switch live categories and All Categories; no sample records should appear when results are empty or requests fail.
4. Create one clearly named disposable test activity, e.g. `Stage 5 temporary verification`, with a future start, optional end crossing midnight, location/address and positive capacity. Check invalid fields before publishing. Confirm only one record is inserted, with author_id matching the signed-in Auth UUID and category_id matching the selected catalog record.
5. Confirm the successful activity's details, Feed and Explore entry, local date grouping, organizer, and initial `0 going`. In Supabase Table Editor verify the record UUID/fields. Do not add fake attendees.
6. Edit the test record. Change title/category/location/start, clear address/end/capacity, save, and verify both the database row and lists/details reflect the confirmed edit. A category change should remove it from an incompatible active filter.
7. If needed, verify with a separate test user that organizer controls are absent and direct other-user writes are blocked by the deployed RLS. Use the rollback-only SQL tests in a disposable project for policy verification; do not weaken policies.
8. Delete **only the newly created test record** through its confirmation alert. Verify the UI returns, both lists no longer include its UUID, and Supabase no longer contains that record. Leave unrelated rows untouched.
9. Test offline reads/saves and retry, empty categories, a missing detail UUID, session expiration/restoration, profile editing, and app reopening. Live provider testing requires an actual authorized account; no fake-auth bypass exists.

## Known limits

- Stage 5 is fetch/refresh based; it does not subscribe to realtime events or add background polling. “Live Feed” means backend records rather than static fixtures.
- Pages load 50 rows and expose Load More; offset pagination may need a refresh if other clients insert/reorder records during paging.
- Participant counts are real, but names/avatars are not fetched, and joining/saving/skipping are unavailable.
- Category artwork remains the cover even if an existing record has a remote cover reference. Uploads and remote-image rendering are outside Stage 5.
- There is no offline write queue. A network interruption after the server commits but before the response arrives can require checking the refreshed list before retrying creation.
- This preserves existing single-community visibility; organization isolation is not introduced.
- Supabase RLS may deliberately make missing and unauthorized mutations indistinguishable; zero-row update/delete responses display a safe ownership/unavailable error.

## File report and Git status

Created:

- `AfterWork/Data/DTO/ActivityRecordDTO.swift`
- `AfterWork/Models/ActivityDraft.swift`
- `AfterWork/Features/Activities/ActivityListViewModel.swift`
- `AfterWork/Features/Activities/ActivityFormViewModel.swift`
- `AfterWork/Features/Activities/ActivityDetailsViewModel.swift`
- `AfterWork/Features/Activities/ActivityDetailsView.swift`
- `AfterWork/Features/Activities/ActivityListStatusView.swift`
- `AfterWorkTests/ActivityTests.swift`
- `AfterWorkTests/ActivityViewModelTests.swift`
- `AfterWorkTests/ActivityRepositoryTests.swift`
- `supabase/tests/004_activity_crud.sql`
- `STAGE5.md`

Modified:

- `AfterWork/App/MainTabView.swift`
- `AfterWork/Components/ActivityCard.swift`
- `AfterWork/Components/ActivityRow.swift`
- `AfterWork/Components/CategoryChip.swift`
- `AfterWork/Components/CategoryFilter.swift`
- `AfterWork/Core/Auth/AuthManager.swift`
- `AfterWork/Data/Repositories/ActivityRepository.swift`
- `AfterWork/Features/CreateActivity/CreateActivityView.swift`
- `AfterWork/Features/Explore/ExploreView.swift`
- `AfterWork/Features/Feed/FeedView.swift`
- `AfterWork/Models/Activity.swift`
- `AfterWork/Models/ActivityCategory.swift`
- `AfterWork/Resources/MockData/MockActivities.swift`
- `README.md`

Deleted: none. Existing migrations, base DTOs, Auth/onboarding/provider implementations, Profile, and backend checker are preserved. At the implementation review checkpoint, all changes were unstaged on `feature/stage-5-activities`; no staging, commit, push, or merge had been performed. The user subsequently authorized committing and pushing Stage 5. Live CRUD verification remains pending as documented above.

References used to verify API behavior: [Supabase Swift relational selects and counts](https://supabase.com/docs/reference/swift/select), [Swift update representations](https://supabase.com/docs/reference/swift/update), [Swift deletion](https://supabase.com/docs/reference/swift/delete), [PostgREST resource embedding](https://docs.postgrest.org/en/stable/references/api/resource_embedding.html). SDK signatures were also checked against the installed pinned 2.55.3 source.
