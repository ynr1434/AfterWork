Stage 4 authentication is implemented on `feature/stage-4-auth`. See [STAGE4.md](STAGE4.md) for architecture, validation results, the additive migration, and exact provider setup. Earlier stage notes below describe their original implementation and validation, not live provider verification. The local configuration example was deleted before Stage 4 and that deletion is preserved by request.

# AfterWork

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
| activity_photos | Photo metadata only, no Storage buckets or upload implementation |
| activity_mentions | Activity/comment mentions, with matching activity/comment foreign keys |
| notifications | Private recipient records, created by trusted server code later |

All rows use UUID keys and timestamptz creation dates. Profiles, activities, participants, and comments share an updated-at trigger. Constraints reject invalid capacities, time ranges, coordinates, empty titles/comments, duplicate participation, and duplicate mentions. Indexes support feed dates, categories, authors, participants, comments, notification timelines, and foreign-key cleanup.

Deleting an Auth user cascades their profile and authored content; deleting an activity cascades its participants, comments, photos, and mentions. Notification activity/actor references become null when those rows are deleted. Category deletion is restricted while activities reference it. Photo-row deletion does not delete a Storage object; future Storage integration must handle that separately. Participant capacity is informational at this stage; atomic capacity enforcement belongs to the future join flow.

### Access policies

All eight tables have RLS enabled. Migration 001 grants no anonymous access; migration 002 permits only anonymous SELECT on the non-sensitive category catalog. Grants explicitly remove default privileges and restrict client-writable columns, preserving IDs, ownership, relationships, and timestamps.

- Authenticated users can read profiles, categories, activities, participants, comments, and photo metadata. This is one shared coworker community, not a multi-tenant organization model. Profile email is nullable, informational, and visible to authenticated users; keep it null if it should not be shared.
- Users can update their own profile presentation fields. Profile provisioning and email synchronization are reserved for trusted server code in the future Auth stage; there is no automatic Auth trigger yet.
- Activities and comments can be created as oneself and edited/deleted only by their author.
- Participant records belong to the current user; only status is editable.
- Photo inserts require the current uploader and a storage path beginning with their UUID plus `/`; users can delete their own metadata. This does not replace future Storage object policies.
- Mentions are readable only by sender/recipient. Inserts require the current sender to own the source activity or source comment. A composite foreign key prevents cross-activity comment references. Mentions cannot be updated and can be deleted by their sender.
- Notifications are visible only to their recipient. The only client-editable field is `is_read`. No client insert/delete permission or policy exists.
- Categories are read-only from clients. Trusted server operations retain service-role privileges; that role is never configured in the app.

## Supabase Development Setup

1. Create a new **development** project in Supabase Dashboard and wait until it is ready. Keep the database password outside this repository.
2. Open **SQL Editor > New query**.
3. Run `supabase/migrations/001_initial_schema.sql` once. If Stage 3 was already applied, skip this step; do not recreate the tables.
4. Run `supabase/migrations/002_public_category_read.sql` once. This is required for the connection test before Auth exists: it grants read-only access to the public category catalog and leaves RLS enabled. It grants no access to private data or writes.
5. In **Table Editor**, verify the eight tables: profiles, categories, activities, activity_participants, comments, activity_photos, activity_mentions, notifications.
6. Verify `categories` has 12 rows.
7. Verify RLS is enabled on all eight tables. Optionally run this in SQL Editor:

   ```sql
   select tablename, rowsecurity
   from pg_tables
   where schemaname = 'public'
     and tablename in ('profiles', 'categories', 'activities', 'activity_participants',
                       'comments', 'activity_photos', 'activity_mentions', 'notifications');
   select count(*) from public.categories;
   ```

8. Get the **Project URL** from the project's **Connect** panel.
9. Get the **publishable** key from **Settings > API Keys**, or the legacy public **anon** key. Never use a service-role or secret key.
10. Create `Configuration/Config.xcconfig` with the settings below if the local file does not exist. A blank local copy was prepared during Stage 3.5. Do not overwrite a configured copy.
11. Paste the values **only into Configuration/Config.xcconfig**:

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
    AfterWork/Data/DTO/*.swift Tests/Stage3FoundationChecks.swift \
    -o /tmp/AfterWork-Stage3-checks
  /tmp/AfterWork-Stage3-checks
  ```

No live authenticated Supabase request has been tested because no project credentials/session are configured. No new app permissions or entitlements were added.

### Stage 3.5 validation

The local Config.xcconfig is blank and Git-ignored. Both migrations and their SQL security checks passed in the isolated PostgreSQL-compatible runtime. The initial migration remains unchanged. Missing-configuration handling remains covered by the Stage 3 Swift checks; the debug screen exposes only safe app errors. Live backend success requires the manual setup above.

Debug and Release builds passed on iPhone 17 / iOS 26.1 Simulator. The Debug mock feed launched with blank configuration; the Profile checker showed Not configured before and after pressing Test. The Release binary excludes BackendDebugView and its test button.
