## Stage 10 — Remote Push Notifications


## Stage 15 — Final MVP UI/UX Polish

Continued from the colleague's `1ac5d9d` on `feature/stage-15-mvp-polish`, based on the Stage 10 main commit `fe90b5a`. Stages 11–14 remain out of scope. See [STAGE15.md](STAGE15.md) for the implementation audit, exact verification, file inventory and remaining release prerequisites.

- Adaptive card surfaces, error colors, reusable inline messages and empty states preserve the existing AfterWork design.
- Feed is a separate mock carousel of 12 Almaty cafés, restaurants, pubs and bars, with friend-group occasion copy. It does not duplicate Explore or send activity/engagement writes to Supabase. Swipe or use Previous/Next to browse ideas.
- Activity cards and rows use local calendar/time-zone formatting and adapt to accessibility text sizes. Native five-tab navigation is retained.
- Create preserves backend validation and duplicate-submit protection; category selection uses a native navigation list. The editor scales with Dynamic Type. Publish is the creation action; no extra keyboard Done button is added.
- Details separates information, attendance, photos, discussion, and calendar actions; Retry reloads all associated sections. Photo thumbnails use private signed access, accessible actions, progress/error states, and a paged full-screen viewer.
- Comments preserve mention IDs, ownership controls, draft text on failure, and deletion retry. Notifications retain APNs routing and guard against late refreshes undoing read state.
- Authentication buttons preserve provider branding and existing OAuth logic. Main-tab state is recreated when the authenticated account changes.
- Loading/error/empty presentation, dark appearance, keyboard scrolling, VoiceOver labels, touch targets, and Reduce Motion support were reviewed. No new dependency, backend migration, signing change, or remote deployment was introduced.
- Target remains iOS 17+, with iPhone-first layouts. Simulator visual checks covered small (16e) and standard (17 Pro) devices on iOS 26.1. The large 17 Pro Max visual check did not complete; physical-device and full iPad certification are also still required.
- Full XCTest suite: **82 tests passed** after replacing obsolete Feed-action cases with coverage for the 12 place ideas. An initial synchronous actor-isolated test hit a Swift runtime deinit crash; running that test as async fixed its invocation without removing assertions.

### Stage 15 manual beta QA still required

- Repeat Google/Apple sign-in, onboarding, session restore, logout/account switch using the intended development project and provisioned device.
- Create/edit/delete only disposable test activities; verify one Publish, organizer attendance, Save/Unsave, Skip, Join/Leave, capacity and participant counts with two accounts.
- Check discussion/mentions/notification links and badges; upload/view/page/delete private test photos and verify unrelated records remain untouched.
- Test calendar/reminders and real-device APNs foreground/background/cold-start routing; Simulator XCTest does not certify delivery or provisioning.
- Review long titles/comments, normal and accessibility text sizes, VoiceOver, Reduce Motion, keyboard overlap, landscape, offline/retry and populated states in light/dark mode.
- Release prerequisites: account deletion entry point, in-app privacy policy/support links, UGC reporting/blocking/moderation review, App Store privacy declarations and SDK required-reason API audit, final icon/metadata, and Apple/APNs provisioning. These are separate from the intentionally skipped discovery/maps/advanced-profile features. This app is not claimed to be App Store approved.


Stage 10 is prepared locally on `feature/stage-10-remote-push`. See [STAGE10.md](STAGE10.md) for the complete architecture/security report, file inventory, validation, exact setup/deployment instructions and physical-device verification plan. **No migration, function, secrets or webhook has been deployed remotely.**

- Existing Stage 8 `notifications` INSERTs remain the source of truth for `mention` and `activityComment`. One secured Database Webhook invokes the new Supabase Edge Function, which rereads the canonical recipient and sends generic alerts through the correct HTTP/2 APNs environment. No new in-app source, activity broadcasts or Firebase backend is added.
- Profile offers an explicit **Enable Notifications** action, status, retry/opt-out and Open Settings when denied. Tokens are received by a lightweight AppDelegate adaptor, held in memory, and registered with the existing Supabase client. Permissions are never requested automatically on first launch.
- Apply only the additive `supabase/migrations/20261014120000_stage10_push_notifications.sql` after review. Private `push_device_tokens` registrations use an authenticated session and Keychain-held installation proof; RLS and narrow RPCs protect account transfers, rotation, multiple devices and logout cleanup. `push_deliveries` provides bounded per-notification/installation claims and guarded invalid-token handling.
- APNs environment comes from the running app's signed aps-environment, not DEBUG. Current signing remains unchanged; `Configuration/AfterWorkPush.entitlements` is an optional template for a properly provisioned paid team. The bundle ID is still `com.kingz.AfterWork.AfterWork`.
- Provider keys and APNS_KEY_ID / APNS_TEAM_ID / APNS_PRIVATE_KEY / APNS_TOPIC belong only in **Edge Function Secrets**, together with a separate PUSH_WEBHOOK_SECRET. The endpoint-specific JWT gateway exception requires its mandatory private `x-afterwork-webhook-secret` header. No keys belong in Swift, Info.plist, xcconfig, SQL or Git.
- Foreground alerts refresh the existing notification list/count without marking read. Taps wait for auth, revalidate recipient/activity/type, open existing Details, and require server read confirmation. The in-app badge now uses the exact backend unread count. Local reminders remain independent; no app-icon badge or unsupported background execution is added.
- Explicit logout removes only the current installation before clearing auth. Cleanup failure blocks logout with retry. Registration writes are serialized and late APNs callbacks cannot re-register during cleanup.
- Debug/Release builds, XCTest, Deno and isolated SQL validation are documented in [STAGE10.md](STAGE10.md#completed-locally-and-validation). **Real APNs delivery remains unverified**: paid signing, physical devices, server credentials, hosted deployment and webhook setup are manual prerequisites. Docker's local daemon is stopped, so the full local Edge runtime could not be started; Deno validation ran independently.

## Stage 6 — Engagement

Stage 6 adds server-backed activity engagement on `feature/stage-6-engagement`.

- Feed cards respond to native swipes: left skips and right saves. A swipe never joins an activity; **I'm Going** is always explicit.
- Save/Unsave and Skip persist per user in `activity_user_actions`. Skipped activities leave Feed but remain visible in Explore.
- Join/Leave uses `activity_participants` and the authenticated user ID. `join_activity` locks the activity row and enforces `max_participants` atomically.
- The activity organizer is inserted as `going` by an idempotent database trigger.
- Details shows saved/going/full state, participant count, and a Participants screen with initials and public profile role information.
- Profile loads real upcoming joined, saved, and created activity sections. RLS limits engagement writes to the current user; participant reads remain available for activity UI.

Apply `supabase/migrations/20261013150000_stage6_engagement.sql` after the existing migrations before using Stage 6 against Supabase. Run `supabase/tests/005_activity_engagement.sql` in a disposable database to validate organizer attendance, idempotent joining, capacity, ownership RLS, and engagement state. Photos, comments, mentions, maps, calendar, notifications, and recommendations remain outside this stage.

## Stage 5 — Real Activities

Stage 5 is implemented for review on `feature/stage-5-activities`. Stage 4 is merged into approved main. See [STAGE5.md](STAGE5.md) for the complete implementation report, file inventory, tests, manual verification and limitations.

- Feed and Explore use real Supabase records, real category UUID filters, pull-to-refresh, loading/empty/error states, and bounded pagination. There is no silent mock fallback.
- `ActivityRepository` now supports categories, upcoming/category/author reads, detail reads, and create/update/delete. It reuses the existing client and derives ownership from the SDK session.
- One relational query embeds category, organizer and attendance count filtered to `going`. Domain IDs are UUIDs; timestamps remain Date/timestamptz with local display and exclusive Today/Tomorrow/This Week/Later groups.
- One native form handles creation and author-only editing; details include a confirmed author-only deletion flow. Join/Save/Skip remain clearly unavailable.
- Existing activity RLS and column grants support this stage unchanged. **No new migration is required or deployed.** The rollback-only `supabase/tests/004_activity_crud.sql` verifies ownership and CRUD constraints in a disposable database.
- Debug/Release simulator builds, 25 XCTest cases and isolated SQL checks pass. The live DEBUG category checker returned **Connected — 12 categories found**. Live activity CRUD verification still requires a signed-in simulator session; no temporary activity has yet been written by validation.

Use the configured project and a test account, create one disposable future activity, verify its UUID in Supabase/Feed/Explore/Details, edit and clear optional fields, then confirm deletion removes only that test UUID. Full steps and provider prerequisites are in [STAGE5.md](STAGE5.md#manual-live-verification).

Stage 4 authentication was merged into `main` from `feature/stage-4-auth`. See [STAGE4.md](STAGE4.md) for architecture, validation results, the additive migration, and exact provider setup. Earlier stage notes below describe their original implementation and validation, not live provider verification. The local configuration example was deleted before Stage 4 and that deletion is preserved by request.

# AfterWork

## Stage 7 — Calendar & Local Reminders

Stage 7 adds device-local Apple Calendar and reminder support for activities the
current user is going to. Calendar access is requested only when the user taps
**Add to Calendar**; the app uses the default writable calendar and stores the
activity-to-event identifier mapping only in local `UserDefaults`. Existing
mapped events are reused and updated instead of duplicated, and only events
created through that mapping can be removed by AfterWork.

Local notifications are requested only when a reminder is selected. Supported
options are none, 10 minutes, 30 minutes, and 1 hour before the activity. A
stable activity-based identifier replaces an existing reminder, skips reminders
whose calculated time has passed, and cancels reminders when a non-organizer
leaves. Calendar events are preserved on leave and can be removed manually;
activity edits update the mapped event and reschedule its reminder after the
backend save succeeds. Calendar events, permissions, and reminders are
device-local and are not stored in Supabase or synchronized between devices.

AfterWork is an iOS app for coworkers to discover and join activities after work, from volleyball and cinema to coffee and board games.

## Tech stack

- Swift
- SwiftUI
- iOS 17+
- MVVM (feature views are in place; models and view models will be added when needed)
- async/await for future asynchronous work
- Swift Package Manager with the official Supabase Swift SDK (2.55.3)

## Current stage

Stage 3.5 — real-project connection readiness

Current implemented features:

- Five native tabs with independent NavigationStacks
- One prominent activity card in Feed, category filters, and local sample browsing
- Explore rows grouped into Today, Tomorrow, This week, and Coming up when needed
- Six mock activities with relative dates, participant counts, and organizer information
- Category-based SwiftUI cover artwork; no remote images
- Polished Create and Notifications empty states, plus a static sample profile
- Semantic Light/Dark colors and lightweight spacing, radius, and typography tokens
- Reusable cards, rows, chips, avatars, buttons, empty states, and a loading view

Skip cycles through mock cards. Save, Going, and Create activity display preview messages only. Nothing is saved or submitted. Screens still use mock data only. The production UI does not initialize the backend. A temporary DEBUG-only checker under Profile can explicitly test the configured project.

## Project structure

```text
AfterWork.xcodeproj/
AfterWork/
├── App/                 # Existing entry point and MainTabView
├── Core/
│   ├── Design/         # AppColors, AppSpacing, AppCornerRadius, AppTypography
│   └── Supabase/       # Configuration, shared client, safe errors
├── Data/
│   ├── DTO/            # Eight Codable database row types
│   └── Repositories/   # Read-only activity and profile queries
├── Models/              # Activity and ActivityCategory, UI prototype only
├── Components/          # Shared presentation components
├── Features/
│   ├── Feed/
│   ├── Explore/
│   ├── CreateActivity/
│   ├── Notifications/
│   └── Profile/
└── Resources/
    ├── Assets.xcassets/ # Adaptive semantic colors and existing app assets
    └── MockData/        # MockActivities
```

Shared components: ActivityCard, ActivityCover, ActivityRow, CategoryChip, CategoryFilter, AvatarView, AvatarGroup, PrimaryButton, SecondaryButton, EmptyStateView, and LoadingView.

The mock model stores a single `startsAt` date for both date and time. Shared schedule formatting respects the user's locale. Samples are generated relative to the day the app launches, with Board Games on the nearest Friday. Explore avoids duplicate date groups and places later-week samples under Coming up if necessary.

Views contain presentation and small transient UI state. No view models are needed until feature behavior is introduced. The existing synchronized Xcode group discovers source files automatically.

## Appearance and accessibility

Semantic asset colors support Light and Dark Mode. Text uses system styles for Dynamic Type, compact rows reflow at accessibility sizes, and screens scroll. Interactive controls provide at least 44-point targets. Decorative artwork is hidden from VoiceOver; filters expose selection and action buttons have descriptive labels.

Previews include ActivityCard (Light and Dark with large text), CategoryChip, AvatarView/AvatarGroup, PrimaryButton, Feed, and other feature screens. Inspect all tabs at large Dynamic Type sizes and with VoiceOver before extending the prototype.

## Build

Open AfterWork.xcodeproj in Xcode and select the AfterWork scheme. Both Debug and Release target iOS 17.0. Install the iOS platform required by your Xcode version in Xcode > Settings > Components, then choose an available simulator or device.

Inspect schemes and destinations before building:

```sh
xcodebuild -list -project AfterWork.xcodeproj
xcodebuild -showdestinations -project AfterWork.xcodeproj -scheme AfterWork
```

With the iOS platform installed, a compile-only device build can run without signing:

```sh
xcodebuild -project AfterWork.xcodeproj -scheme AfterWork \
  -configuration Debug -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

Running on a physical device requires selecting your development team under Signing & Capabilities.

## Future planned integrations

- Connect the existing mock UI to Supabase after Auth
- Sign in with Apple
- Google Sign In
- EventKit
- Local and remote notifications
- Activity feed, categories, filters, creation, and joining
- Comments
- Mentions
- Photos

These integrations and real product behaviors remain planned. The UI continues to use local mock data only.

## Supabase foundation

The official package is [supabase/supabase-swift](https://github.com/supabase/supabase-swift), resolved to **2.55.3**, with an exact version requirement. The app links only its `Supabase` product because `SupabaseClient` coordinates authenticated database access. That product brings its own Auth/PostgREST/Realtime/Storage/Functions modules and required transitive packages; none are separately added to the app. No Auth UI, uploads, realtime subscriptions, or function calls are implemented.

The validated transitive resolutions are swift-crypto 4.5.2, swift-asn1 1.7.3, swift-http-types 1.8.0, swift-clocks 1.1.1, swift-concurrency-extras 1.4.1, and xctest-dynamic-overlay 1.13.1. Supabase itself is pinned in the project. Xcode did not retain a workspace Package.resolved file in this environment; retain that file under version control when Xcode generates it for your workspace.

`SupabaseManager.shared.client` lazily creates one client and throws a `DatabaseError` if configuration is missing or invalid. Only the DEBUG connection checker requests it, after you press Test. Future signed-in features can inject this client into `ActivityRepository` or `ProfileRepository`. The repositories expose bounded upcoming-activity reads and single activity/profile reads, return DTOs, preserve cancellation, and convert other SDK errors to safe app errors. Missing/invisible single rows return nil. Activity and profile reads require a future authenticated session. Migration 002 makes only the non-sensitive category catalog readable with a public key, allowing a pre-Auth connection check.

DTOs intentionally remain separate from the Stage 2 `Activity` UI model. Future integration must combine activity rows with category, profile, and participant data before constructing UI models; no fake participant counts are inferred. `CategoryDTO.slug` uses database slugs, including `board_games`, while the existing UI enum remains unchanged. Add an explicit mapping when connecting the screens.

### Local Xcode configuration

1. Create the Git-ignored `Configuration/Config.xcconfig` using the settings below.
2. Enter the project URL and **publishable** client key (recommended), or legacy **anon** key, from the Supabase project's Connect panel / Settings > API Keys.
3. Write the URL with the xcconfig slash escape, for example:

   ```xcconfig
   SUPABASE_URL = https:/$()/YOUR_PROJECT_REF.supabase.co
   SUPABASE_ANON_KEY = YOUR_PUBLIC_CLIENT_KEY
   ```

   `//` begins a comment in xcconfig; do not paste an unescaped `https://` URL. The variable name `SUPABASE_ANON_KEY` also accepts a publishable key.
4. Build normally. Debug and Release already use `Configuration/Base.xcconfig`, which optionally includes the local file. `Configuration/Info.plist` carries the expanded values into the app. No manual build-setting wiring is needed.

The app compiles and launches when the local file is absent. Configuration requires HTTPS, rejects unresolved placeholders, rejects secret keys, and accepts legacy JWT keys only with role `anon`. The JWT payload check prevents accidental privileged-key use; it is not signature verification or authentication.

Never commit local `Config.xcconfig`, `.env` files, database passwords, service-role keys, or secret API keys. Never put `service_role` or `sb_secret_` keys in an iOS app. Public client keys are intentionally extractable from a built app; RLS and an authenticated session protect the database. Do not publish configured build-setting dumps or build artifacts as secrets storage. The former example config deletion is preserved; the settings shown above contain placeholders only.

### Database migration

Apply `supabase/migrations/001_initial_schema.sql` once to a fresh Supabase project. It runs in a transaction and creates:

| Table | Purpose |
| --- | --- |
| profiles | Coworker identity; UUID references `auth.users(id)` |
| categories | Twelve seeded category slugs and SF Symbols |
| activities | Author, category, times, location, optional capacity and cover |
| activity_participants | One status per activity/user: interested, going, declined |
| comments | Activity comments with author ownership |
| activity_photos | Metadata for private activity photo objects in the `activity-photos` Storage bucket |
| activity_mentions | Activity/comment mentions, with matching activity/comment foreign keys |
| notifications | Private recipient records, created by trusted server code later |

All rows use UUID keys and timestamptz creation dates. Profiles, activities, participants, and comments share an updated-at trigger. Constraints reject invalid capacities, time ranges, coordinates, empty titles/comments, duplicate participation, and duplicate mentions. Indexes support feed dates, categories, authors, participants, comments, notification timelines, and foreign-key cleanup.

Deleting an Auth user cascades their profile and authored content; deleting an activity cascades its participants, comments, photo metadata, and mentions. The app removes private photo objects before deleting an activity; if Storage cleanup fails, activity deletion stops so objects are not orphaned. Notification activity/actor references become null when those rows are deleted. Category deletion is restricted while activities reference it. Activity photos are limited to ten images, resized to at most 2,200 pixels on the long edge, and uploaded as JPEG files no larger than 5 MB. Private image URLs are signed for 15 minutes. Participant capacity is informational at this stage; atomic capacity enforcement belongs to the future join flow.

### Access policies

All eight tables have RLS enabled. Migration 001 grants no anonymous access; migration 002 permits only anonymous SELECT on the non-sensitive category catalog. Grants explicitly remove default privileges and restrict client-writable columns, preserving IDs, ownership, relationships, and timestamps.

- Authenticated users can read profiles, categories, activities, participants, comments, and photo metadata. This is one shared coworker community, not a multi-tenant organization model. Profile email is nullable, informational, and visible to authenticated users; keep it null if it should not be shared.
- Users can update their own profile presentation fields. Profile provisioning and email synchronization are reserved for trusted server code in the future Auth stage; there is no automatic Auth trigger yet.
- Activities and comments can be created as oneself and edited/deleted only by their author.
- Participant records belong to the current user; only status is editable.
- Photos are stored in the private `activity-photos` bucket using `activities/<activity UUID>/<uploader UUID>/<photo UUID>.jpg`. Only the organizer or a going participant can upload. The uploader or activity organizer can delete a photo. Metadata and Storage policies enforce ownership, activity membership, canonical paths, and a maximum of ten photos per activity.
- Mentions are readable only by sender/recipient. Inserts require the current sender to own the source activity or source comment. A composite foreign key prevents cross-activity comment references. Mentions cannot be updated and can be deleted by their sender.
- Notifications are visible only to their recipient. The only client-editable field is `is_read`. No client insert/delete permission or policy exists.
- Categories are read-only from clients. Trusted server operations retain service-role privileges; that role is never configured in the app.

## Supabase Development Setup

1. Create a new **development** project in Supabase Dashboard and wait until it is ready. Keep the database password outside this repository.
2. Open **SQL Editor > New query**.
3. Run `supabase/migrations/001_initial_schema.sql` once. If Stage 3 was already applied, skip this step; do not recreate the tables.
4. Run `supabase/migrations/002_public_category_read.sql` once. This is required for the connection test before Auth exists: it grants read-only access to the public category catalog and leaves RLS enabled. It grants no access to private data or writes.
5. Run `supabase/migrations/20261014110000_stage9_activity_photos.sql` once to create the private Storage bucket and Stage 9 photo access policies. This migration is additive and is not applied by the app.
6. In **Storage**, verify the private `activity-photos` bucket exists and its size/MIME restrictions are 5 MB and `image/jpeg`.
7. In **Table Editor**, verify the eight tables: profiles, categories, activities, activity_participants, comments, activity_photos, activity_mentions, notifications.
8. Verify `categories` has 12 rows.
9. Verify RLS is enabled on all eight tables. Optionally run this in SQL Editor:

   ```sql
   select tablename, rowsecurity
   from pg_tables
   where schemaname = 'public'
     and tablename in ('profiles', 'categories', 'activities', 'activity_participants',
                       'comments', 'activity_photos', 'activity_mentions', 'notifications');
   select count(*) from public.categories;
   ```

10. Get the **Project URL** from the project's **Connect** panel.
11. Get the **publishable** key from **Settings > API Keys**, or the legacy public **anon** key. Never use a service-role or secret key.
12. Create `Configuration/Config.xcconfig` with the settings below if the local file does not exist. A blank local copy was prepared during Stage 3.5. Do not overwrite a configured copy.
13. Paste the values **only into Configuration/Config.xcconfig**:

    ```xcconfig
    SUPABASE_URL = https:/$()/PROJECT_REF.supabase.co
    SUPABASE_ANON_KEY = YOUR_PUBLIC_CLIENT_KEY
    ```

    The `$()` escapes the slash pair because xcconfig treats `//` as a comment. The ANON_KEY setting accepts either public key format. This file is ignored by Git; do not paste real values into Swift, README, or the example config.
12. Rebuild and run the **Debug** configuration in Xcode. Values are bundled at build time, so changing the config requires rebuilding and relaunching. Debug and Release configuration wiring is already set up; no manual build-setting changes are needed.
13. Open **Profile**, tap the **wrench/screwdriver** toolbar button (**Backend Connection**), then tap **Test Supabase Connection**.
14. Expect **Connected — 12 categories found**. A nonempty result is success; a different count includes a seed-data reminder. An empty result is a failure with migration/RLS guidance. Missing values show **Not configured** without constructing a client or issuing a request. Other failures show safe troubleshooting guidance without raw server errors or credentials.

The checker and its navigation link are compiled only under `#if DEBUG` and are excluded from Release. It only selects categories; it does not authenticate, write rows, or replace mocks. Opening the screen validates local configuration but does not contact Supabase until Test is pressed. Do not disable RLS to fix a failed test.

For database validation in an isolated development project, run `supabase/tests/001_security.sql` and `supabase/tests/002_public_category_read.sql` as `postgres` after both migrations. Tests roll back their changes; if a SQL client leaves a failed transaction open, run ROLLBACK. The second test verifies public catalog reads, denied catalog writes, and private-table isolation.

No remote project was created or modified automatically. Real connectivity remains unverified until you provide the local configuration and run the test. No Auth providers, Storage buckets, or notification setup are required for Stage 3.5.

Dashboard SQL execution does not register this file in Supabase CLI migration history. When adopting the CLI later, reconcile that already-applied migration before running `db push`; do not apply it twice.

References: [Swift initialization](https://supabase.com/docs/reference/swift/initializing), [API keys](https://supabase.com/docs/guides/api/api-keys), and [RLS and grants](https://supabase.com/docs/guides/database/postgres/row-level-security).

### Stage 3 validation

- Package resolution and iPhone 17 / iOS 26.1 Simulator Debug build passed without credentials; deployment target remains iOS 17.0.
- The migration and `supabase/tests/001_security.sql` passed in an isolated PGlite PostgreSQL runtime with minimal Supabase Auth roles/schema stubs. This validates SQL, constraints, grants, and RLS locally; rerun against the actual Supabase development project to validate its environment. No remote migration has been applied.
- Standalone Swift checks cover missing/invalid configuration, rejection of server keys, acceptance of public-key formats, and all eight DTOs' snake_case/date/optional-field coding. Run from the repository root:

  ```sh
  xcrun swiftc -parse-as-library \
    -module-cache-path /tmp/AfterWork-Stage3-test-cache \
    AfterWork/Core/Supabase/DatabaseError.swift \
    AfterWork/Core/Supabase/SupabaseConfiguration.swift \
    AfterWork/Models/Activity.swift AfterWork/Models/ActivityCategory.swift \
    AfterWork/Data/DTO/*.swift Tests/Stage3FoundationChecks.swift \
    -o /tmp/AfterWork-Stage3-checks
  /tmp/AfterWork-Stage3-checks
  ```

No live authenticated Supabase request has been tested because no project credentials/session are configured. No new app permissions or entitlements were added.

### Stage 3.5 validation

The local Config.xcconfig is blank and Git-ignored. Both migrations and their SQL security checks passed in the isolated PostgreSQL-compatible runtime. The initial migration remains unchanged. Missing-configuration handling remains covered by the Stage 3 Swift checks; the debug screen exposes only safe app errors. Live backend success requires the manual setup above.

Debug and Release builds passed on iPhone 17 / iOS 26.1 Simulator. The Debug mock feed launched with blank configuration; the Profile checker showed Not configured before and after pressing Test. The Release binary excludes BackendDebugView and its test button.

### Stage 8 — Comments & Mentions

- Activity Details includes chronological comments with a validated composer.
- Comment authors can edit or delete their own comments; backend RLS enforces ownership.
- Typing `@` searches visible coworker profiles and inserts a stable user-ID mapping for mention persistence.
- Mentions are rendered with emphasis and create in-app notifications through database triggers.
- Comments on another user's activity create an activity-comment notification for the owner; self-comments are ignored.
- Notifications are read from the current user's rows, support mark-as-read and activity navigation, and expose an unread tab badge.
- The additive Stage 8 migration adds secure server-side notification triggers without granting notification INSERT access to clients.
- Remote push delivery, realtime discussion, attachments, and advanced notification deduplication remain future work.
