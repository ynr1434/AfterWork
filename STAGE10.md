# Stage 10 — Remote Push Notifications

Branch: `feature/stage-10-remote-push`, created from clean `main` at `09f9cf2` after verifying local main matched origin/main. The unfinished simulator-demo stashes from the earlier task were not applied. Implementation was initially left unstaged for review; the user subsequently authorized committing, pushing, and merging to main. No remote SQL, webhook setup, secret upload, or deployment was performed for Stage 10.

## Client implementation

`AfterWorkApp` uses a lightweight `UIApplicationDelegateAdaptor(AppDelegate.self)`. The delegate installs one UNUserNotificationCenter delegate at launch, receives APNs tokens and registration errors, handles foreground presentation and user taps. It does **not** prompt or register automatically on first launch.

`PushNotificationManager` is a shared observable service, supplied by RootView. It keeps current APNs token data in memory only, normalizes bytes to lowercase hex without assuming a fixed 32-byte length, manages account-scoped opt-in preferences, registration/retry, and pending navigation. The repository reuses the existing Supabase client. Auth startup/restoration remains owned by AuthManager; there is no separate push authentication flow.

Profile adds a small Notifications section with status, Enable Notifications, Retry Registration, Turn Off Push, and an Open Settings action when permission is denied. Permission is requested only after a signed-in user's explicit Enable action and only if the signing environment is supported. `authorized`, `provisional`, and `ephemeral` map to allowed; denied and unknown statuses are handled safely. An existing local-reminder permission grant does **not** opt the user into remote pushes. Foreground re-entry refreshes settings and re-registers opted-in users, allowing APNs token rotation and last-seen renewal.

`PushInstallation` stores a random installation UUID and 256-bit installation proof in a ThisDeviceOnly Keychain item. UserDefaults contains opt-in preferences and a non-secret registration-possible marker, never APNs/auth tokens or installation secrets. The marker is persisted before upload so an interrupted request/response does not make logout forget possible server state. Keychain identity can survive reinstall; a genuinely new identity is treated as a different installation.

Registration uploads are serialized. Account changes invalidate stale completions, wait for outstanding uploads, and either atomically transfer the proven installation to the current authenticated account or remove its old registration if the new account has not opted in. Token callbacks cannot re-register while opt-out/logout cleanup is running. No caller supplies a target user ID.

### Signing and environment selection

The current bundle ID remains **`com.kingz.AfterWork.AfterWork`**. The current active entitlement file, `Configuration/AfterWork.entitlements`, contains Sign in with Apple and **no aps-environment**. No DEVELOPMENT_TEAM is recorded in the project, and paid membership/provisioning was not verified.

`SigningEntitlements` reads the XML entitlement slot from the running thin 64-bit Mach-O executable's embedded code signature using Foundation. `development` maps to backend `sandbox`; `production` maps to `production`. It does not infer from DEBUG, receipts, a user-editable Info.plist setting, or try another environment. iOS does not expose SecTask entitlement APIs in the public SDK, so no private API is used. Unsigned, malformed, or DER-only signatures without the XML slot fail closed with a safe unavailable message. Verify the final signed/exported app's entitlements when provisioning; the simulator build does not establish a push environment.

`Configuration/AfterWorkPush.entitlements` is an **optional, currently unwired** template preserving Apple sign-in and adding `aps-environment = $(APNS_SIGNING_ENVIRONMENT)`. Existing signing settings and local builds remain unchanged until a developer with an appropriate team intentionally enables it. No background-mode change is required for this alert/tap implementation.

### Logout and invalidation

RootView supplies AuthManager's pre-sign-out hook. It removes the current installation registration **before** clearing the authenticated session, unregisters from APNs locally, and clears push navigation. Other devices are untouched. If a potentially registered device cannot be removed because the network/backend fails, logout is deliberately blocked with a retry message and the current session is preserved. This is the chosen fail-closed privacy tradeoff; users who never enabled push are not blocked by a missing Stage 10 backend migration.

Auth session invalidation clears local push state and unregisters locally. Server registrations reference `auth.sessions` with ON DELETE CASCADE; server lookup also rejects sessions with expired `not_after` and registrations not seen for 30 days. A later account login uses the installation proof to replace/remove stale association. Already accepted APNs alerts cannot be recalled; their payload is generic and tap access is revalidated against the current account.

## Notification source, delivery, and security

The existing Stage 8 notifications table and its comment/mention creation triggers are unchanged. They retain stable types **`mention`** and **`activityComment`** and existing self-notification rules. Stage 10 never creates another in-app notification or broadcasts activity creation.

The delivery path is:

```text
Existing comment/mention trigger
  → INSERT public.notifications (source of truth)
  → manually configured asynchronous Database Webhook
  → send-push-notification Edge Function
  → recipient device registrations
  → HTTP/2 APNs alert
```

A failed push cannot roll back or delete the in-app notification. The webhook is intentionally configured manually; there are no committed HTTP secrets or webhook-trigger credentials in SQL.

### Additive migration

New file: **`supabase/migrations/20261014120000_stage10_push_notifications.sql`**. It was generated with the Supabase CLI and ordered after the repository's already-named Stage 9 migration; no existing migration was edited.

It adds:

- `push_device_tokens`: UUID primary key, authenticated user/session foreign keys, unique installation UUID, hashed installation proof, token, sandbox/production environment, ios platform, version UUID, creation/update/last-seen timestamps. Token/environment is unique, and account/token/session changes rotate the registration version. Recipient/session indexes support lookup and cascade cleanup.
- Token RLS: users can SELECT only their own non-sensitive registration metadata; raw tokens and proof hashes are not granted to clients, even through SELECT *. No direct client INSERT/UPDATE/DELETE grant exists.
- `register_push_device`: narrow SECURITY DEFINER RPC verifying auth.uid(), the JWT's actual valid Auth session, and a 256-bit installation proof. It derives user/session IDs server-side and permits ownership transfer only with the same installation proof. A client cannot steal another installation/token or choose another user. The definer boundary is intentional for cross-account replacement and private auth.sessions lookup, with an empty search_path and restricted EXECUTE.
- `unregister_push_device`: authenticated installation-proof deletion of only that installation. This allows a new account on the same physical installation to remove its old association; another device's proof is required to remove that device. Wrong proofs are rejected.
- `push_deliveries`: server-only delivery claims keyed by notification UUID and stable installation UUID, attempt UUID, registration version, status, attempt budget, lease, and safe APNs result. RLS is enabled with no client grants. Accepted history survives token removal/logout; device references become NULL rather than erasing deduplication history.
- Server-only `push_recipient_devices` and `claim_push_delivery` RPCs, with EXECUTE revoked from PUBLIC/anon/authenticated and granted only to service_role. Recipient lookup checks notification type, read state, self-notification, activity availability, recipient/session ownership, session expiry, and last-seen age.

Every new table has RLS enabled. There is no publicly readable token table, profile token field, permissive public write policy, or client service-role credential. Registration proof hashes and raw tokens remain server-only. Existing RLS and notification triggers are unchanged.

### Edge Function

Source: `supabase/functions/send-push-notification/`:

- `index.ts`: server-only secret loading, actual topic validation, HTTP/2-only client, Deno.serve entry point.
- `handler.ts`: POST/auth checks, bounded 64 KiB event parsing, stored notification lookup, per-installation claims, bounded concurrent multiple-device delivery, safe outcome aggregation/logging.
- `apns.ts`: sandbox/production endpoints, small generic payload, native WebCrypto P-256/ES256 provider JWT, 45-minute warm-worker cache, APNs headers/timeouts, error classification.
- `store.ts`: server-only REST calls with the Edge Function's built-in Supabase service credential; canonical recipient/session lookup, paged devices, claims, results, guarded cleanup.
- `handler_test.ts`: nine credential-free tests with APNs/database doubles and real local verification of generated ES256 signatures.
- `deno.json`: strict checking and test tasks; no third-party runtime dependency is introduced.

`supabase/config.toml` disables gateway JWT checking **only** for this webhook endpoint. The endpoint requires the independent **`x-afterwork-webhook-secret`** header on every request, verified through fixed-size SHA-256 digest comparison. Missing/wrong headers return 401 before database access. It rereads the stored notification by ID; caller-supplied recipient/type/body fields are ignored. A normal anonymous or authenticated client cannot invoke arbitrary recipient pushes using its public key or user JWT.

Required server secrets:

| Name | Source/purpose |
| --- | --- |
| APNS_KEY_ID | Actual Apple APNs key ID |
| APNS_TEAM_ID | Actual paid Apple Developer team ID |
| APNS_PRIVATE_KEY | Entire Apple APNs .p8 private key, server secrets only |
| APNS_TOPIC | `com.kingz.AfterWork.AfterWork` |
| PUSH_WEBHOOK_SECRET | Independent cryptographically random secret, at least 32 characters |
| SUPABASE_URL | Supabase-managed Edge Function environment |
| SUPABASE_SERVICE_ROLE_KEY | Supabase-managed Edge Function environment; server only |

No actual private key, provider JWT, device token, service key, webhook secret, or authorization header is logged or committed. `.p8` files and local Supabase env files are Git-ignored. Key import uses native WebCrypto PKCS#8/P-256; signing uses ES256 with native 64-byte JOSE signatures. JWT claims are iss/team ID and iat/epoch seconds, with kid in its header. Warm-worker reuse avoids signing a new provider token for every alert. Credential rotation requires fresh worker configuration/redeployment.

APNs endpoint is chosen solely from the stored signed-entitlement-derived environment. HTTP/1 fallback is disabled. Requests use the exact bundle topic, push type alert, priority 10, notification UUID collapse/APNs ID, and a five-minute expiration. There is no sandbox/production fallback.

Payload contains only generic alert title/body, default sound, activity_id, notification_id, and the existing stable type. It omits comment text, names, emails, full records, keys and tokens; it remains far below the 4 KiB alert limit. The stored notification remains available inside the authenticated app for full content.

### Outcomes, cleanup, and deduplication

Each notification/installation gets an atomic claim with a 60-second lease and at most three attempts. Concurrent/replayed events cannot resend a sent claim. Retried or expired in-flight claims can be reclaimed after the lease, within the budget. Registration versions prevent stale delivery/cleanup from acting on a transferred or rotated device. Accepted history survives logout/re-registration on the same stable installation.

200 is accepted; network failures, 429, 5xx and ExpiredProviderToken are retryable. Expired provider tokens clear the warm cache. Other 400/403 responses are recorded as failures with safe diagnostics. **BadDeviceToken / DeviceTokenNotForTopic do not delete registrations**, because wrong signing/topic/environment configuration can cause these errors. Confirmed 410 Unregistered removes only the matching registration version whose last_seen is not newer than APNs' invalidation timestamp. Temporary failures never delete tokens.

Logs include notification ID, APNs status, whitelisted reason, outcome, environment, and number of devices. They omit device tokens, proof secrets, authentication headers, keys and private message content.

This is best-effort delivery, not exactly-once APNs or a durable queue. A crash after APNs acceptance and before result persistence may allow a resend after lease expiry; collapse IDs help but are not an exactly-once promise. Database Webhooks/pg_net are asynchronous and should not be assumed to schedule all retries automatically. Transient delivery results can be replayed by a trusted operator after 60 seconds (up to three claims); there is no autonomous retry scheduler or mass replay. A failed push leaves the in-app notification intact.

## Reception, navigation, read state and badges

Foreground remote alerts with valid payloads show a banner/sound only for a signed-in opted-in user and refresh the in-app list/count; reception itself never marks a notification read. Malformed/unrelated remote payloads are ignored. Local calendar reminder notifications retain foreground banner/sound and do not touch remote unread state or create push rows.

A remote tap queues a UUID/type destination through foreground, background, and launch. It waits for authentication when necessary. Before presentation the app fetches the actual notification with current-recipient filtering and confirms its activity/type. A different account cannot open another user's notification. MainTabView presents the existing ActivityDetailsView, which fetches the activity and handles deletion/errors. Initial missing-session restoration preserves a cold-launch pending tap; actual logout/invalidation clears user-scoped destinations.

A visible opened destination triggers NotificationRepository.markAsRead, which now requires a server-returned matching ID/is_read=true instead of treating zero updated rows as success. A network failure retains an error/retry path. The existing in-app list and badge refresh from Supabase, with queued refresh handling for pushes arriving during an existing load. Unread count is an exact backend count of **all** recipient unread rows, not a count of the latest 100 displayed rows. Tests verify a 137-unread example. No iOS app-icon badge was added, so local reminders cannot overwrite one or corrupt the in-app count.

## Completed locally and validation

- Debug simulator build/full XCTest suite: passes (final result recorded below).
- Release simulator build: passes (final result recorded below). No paid provisioning or device archive was validated.
- Tests: 68 XCTest cases, including 16 new push/unread cases and the existing 52 auth/activity/engagement/calendar/comments/photo cases. Coverage includes token hex/length validation, actual environment mapping, missing entitlements, permission opt-in, rotation, account-switch ordering, logout failure and late-token-callback protection, cold-auth pending taps, canonical recipient rejection, read confirmation, foreground local/remote handling, and exact unread counts.
- Deno 2.9.6: strict check, lint/format, and all nine Edge Function tests pass without APNs credentials or network access. Tests verify webhook authorization/validation, stored recipients, multiple devices, deduplication, environment headers, native JWT signature validity, retry classifications and guarded cleanup.
- SQL: new migration and `009_push_notifications.sql` pass in isolated PGlite PostgreSQL with minimal Auth users/sessions/uid/jwt stubs. Prerequisite schema and existing security suites 001/002/003/007 also pass. This validates real SQL/grants/RLS/claims, but not the hosted Supabase environment or the unrelated full Storage stack.
- Supabase CLI **2.120.0** is available through npx. `functions serve send-push-notification --no-verify-jwt` could not start: Docker Desktop's daemon is stopped (`ServeLocalDbInspectError`). Native Deno validation ran independently. No hosted Edge runtime/HTTP/2 negotiation was exercised.
- No Stage 10 Swift warnings remain. Existing warnings in unchanged CalendarManager, LocalNotificationManager, ActivityScheduleViewModel, CommentRepository and older tests remain; Xcode also emits its AppIntents metadata-skipped warning. These are not proof of APNs delivery.
- Real Google/Apple sign-in, onboarding, CRUD, engagement, comments, calendar/reminders and photo flows were not repeated live against the backend; existing automated regression cases pass and their implementations are preserved. No unrelated test data was created/deleted remotely.
- **Real APNs delivery is unverified.** Migration, hosted function, secrets, webhook, paid team, device provisioning and physical-device/two-user tests remain manual prerequisites.

Reproduce local checks with an installed Deno/Supabase CLI and an available simulator:

```sh
xcodebuild -project AfterWork.xcodeproj -scheme AfterWork -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' CODE_SIGNING_ALLOWED=NO test
xcodebuild -project AfterWork.xcodeproj -scheme AfterWork -configuration Release \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

deno check supabase/functions/send-push-notification/index.ts \
  supabase/functions/send-push-notification/handler_test.ts
deno test supabase/functions/send-push-notification/handler_test.ts
deno lint supabase/functions/send-push-notification
git diff --check
```

## Exact manual setup — not performed by Codex

### Apple Developer / Xcode

1. Confirm an active **paid Apple Developer Program** team. A free Personal Team cannot provision the required Push Notifications capability. Do not change the app's team or bundle identifier as a workaround; leave the current signing setup until an authorized paid team is available.
2. In Apple Developer → **Certificates, Identifiers & Profiles → Identifiers**, open the existing explicit App ID **com.kingz.AfterWork.AfterWork**, enable **Push Notifications**, and save. Preserve Sign in with Apple. Regenerate/refresh the relevant development and distribution provisioning profiles.
3. In **Keys → +**, create an APNs authentication key with permissions for the intended topic and APNs environment(s). Download its .p8 once into secure storage outside the repository. Record its actual **Key ID** and the team's actual **Team ID** from membership details. Confirm the key's scope permits every environment you intend to deliver to; a scoped production key must not be assumed to authorize sandbox.
4. In Xcode → **AfterWork target → Signing & Capabilities**, deliberately select the authorized paid team and add **Push Notifications**. Keep `PRODUCT_BUNDLE_IDENTIFIER` unchanged. Do not add background remote-notification mode merely to receive user-visible alerts/taps.
5. Wire `CODE_SIGN_ENTITLEMENTS` to **Configuration/AfterWorkPush.entitlements** only in properly provisioned configurations, or let Xcode add the equivalent aps-environment key to the active entitlement file. If using the template, set **APNS_SIGNING_ENVIRONMENT** to `development` or `production` according to the actual provisioning/export profile; this is not a Debug/Release heuristic. Preserve the Apple sign-in entitlement.
6. Inspect the final signed .app using `codesign -d --entitlements :- /absolute/path/AfterWork.app`. Confirm aps-environment and application identifier match the installed provisioning/export configuration. TestFlight/App Store requires production APNs, as reflected by its final signed entitlement. If the runtime cannot read the supported signature slot, push stays unavailable rather than guessing.
7. Install on a properly signed physical iPhone. Keep current public Supabase config. Sign in and use Profile → **Enable Notifications**; signing unsupported environments should show a safe explanation, not break normal app usage.

### Supabase migration and secrets

1. Open the **existing** hosted project. The local config previously references project **ssvgevdfmwljccjodqyg**; verify that is still the intended development project. Do not recreate its schema.
2. After reviewing it, run **only** `supabase/migrations/20261014120000_stage10_push_notifications.sql` in SQL Editor, after the existing Stage 9 migrations. It is additive and contains no keys/webhook secrets. Dashboard SQL does not automatically reconcile CLI migration history; do not subsequently blindly db-push already-applied migrations.
3. Verify both new tables have RLS enabled, restricted grants and the four RPCs exist. Run `supabase/tests/009_push_notifications.sql` as postgres in a **disposable** Supabase test project; it rolls back. Run database/security advisors after deployment and verify the narrow definer functions/EXECUTE grants; do not disable RLS to make registration work.
4. In **Edge Functions → Secrets**, set APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY (complete PEM from the .p8), APNS_TOPIC=`com.kingz.AfterWork.AfterWork`, and an independent randomly generated PUSH_WEBHOOK_SECRET of at least 32 characters. Keep all real values out of Swift, Info.plist, xcconfig, SQL, README, chat and Git. SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are supplied server-side by Supabase; never place the privileged key in the app.
5. If CLI secret entry is preferred, use `supabase secrets set --project-ref ssvgevdfmwljccjodqyg --env-file /secure/temporary/path/afterwork-push.env` with a protected temporary file outside the repository, then remove that temporary input file securely. Do not put secret values into command history or tracked files. The Dashboard avoids making a repository env file.

### Edge Function deployment

1. Install/authenticate the Supabase CLI under an authorized account; the CLI is available here through `npx --yes --registry=https://registry.npmjs.org supabase` if no global binary exists. Local serving also requires Docker Desktop running and a local Supabase stack.
2. From this repository run the local Deno checks above. For hosted deployment, explicitly deploy **only** this function:
   ```sh
   supabase functions deploy send-push-notification \
     --project-ref ssvgevdfmwljccjodqyg --no-verify-jwt
   ```
   CLI signatures were checked with --help. `supabase/config.toml` records endpoint-specific verify_jwt=false. This is safe only with the mandatory independent secret validation included in the function; do not remove that validation or disable JWT checks for other functions.
3. Confirm runtime support for `Deno.createHttpClient({http2:true,http1:false})`, WebCrypto P-256, and outbound APNs HTTP/2 from the hosted environment. A missing API/configuration returns a safe 503; this was not hosted-tested locally because Docker is stopped and nothing was deployed.
4. Set/rotate secrets and redeploy/restart workers when changing APNs credentials. Never expose keys in a public function response. Provider 403 errors require checking actual key/team/topic/environment scope; changing environments blindly is not a fix.

### Database Webhook

1. Open **Database → Webhooks → Create webhook** (enable the Database Webhooks/pg_net integration in this project if required).
2. Choose **public.notifications** and event **INSERT only**. Do not hook comments/mentions separately, UPDATE is_read, or activity creation.
3. Choose HTTP POST to:
   `https://ssvgevdfmwljccjodqyg.supabase.co/functions/v1/send-push-notification`
4. Set **Content-Type: application/json** and **x-afterwork-webhook-secret: the same private PUSH_WEBHOOK_SECRET value**. Configure a suitable HTTP timeout (e.g. 30 seconds for a small device set). Do not use a user JWT or publishable key as this secret and do not commit generated webhook SQL containing it.
5. Save. A standard Database Webhook INSERT body must have type=INSERT, schema=public, table=notifications, and record.id=<stored notification UUID>. The function ignores the caller's other record fields and rereads the database row.
6. Trigger one real comment/mention through a test account. Confirm the existing in-app row, webhook invocation, Edge Function logs and APNs outcome. Wrong/missing webhook secrets must return 401 before any delivery. Unsupported type, deleted activity, self-notification, missing or already-read row is safely skipped.
7. Inspect **Edge Functions → send-push-notification → Logs** and `push_deliveries` as an administrator. Safe fields include notification/installation IDs, status, attempt budget, environment and reason; do not export/log raw tokens, proof hashes, keys or headers. Inspect webhook/pg_net failures if no function invocation occurs.
8. For retryable delivery results, wait at least 60 seconds and replay that specific stored notification INSERT event through the secured endpoint using the private header, within the three-attempt limit. There is no automatic retry scheduler. After fixing permanent credential errors, any targeted log reset/replay is an explicit administrator action, with duplicate risk assessed first. Do not mass-broadcast old notifications.
9. Maintain server-only retention/cleanup of old delivery logs as appropriate. Token rows disappear on logout, confirmed APNs invalidation, user/session deletion; dormant rows are excluded after 30 days and can be pruned by reviewed server maintenance.

## Manual end-to-end verification plan

**A — Registration:** sign into a provisioned physical iPhone, tap Enable in Profile, grant permission once, confirm the APNs delegate succeeds and exactly one token row is associated with that installation/auth user/session. Verify environment matches signed aps-environment. Repeat registration to confirm no duplicates; check a denied permission/Open Settings path.

**B — Mention:** User A mentions User B in a comment. Verify the existing type `mention` in-app row, webhook POST, server-only device lookup, APNs 200 acceptance, actual alert on B's device, correct Details on tap, confirmed read state and exact unread tab count. Test a cold launch with authentication required before resolving the pending destination.

**C — Comment:** B comments on A's activity. Verify the existing `activityComment` row and push to A. A self-comment/self-mention must not generate a new self-notification/push. No activity-creation broadcast should occur.

**D — Foreground/local reminders:** keep the app foregrounded, trigger a remote mention, verify one banner/sound plus in-app refresh and no automatic read. Schedule an existing local reminder separately; verify it remains independent and does not modify remote unread counts.

**E — Logout/account switch:** sign out; verify only the current installation row is removed and pending destinations disappear. Test offline cleanup failure: logout should report retry and preserve the authenticated session. Reconnect/retry. Log into a different account on the same installation, verify proof-based transfer/cleanup, and confirm old-recipient taps cannot expose their activity. No unrelated device registration may be deleted.

**F — Multiple devices/environment:** sign B into two properly provisioned devices, enable each, and verify both receive a valid notification. Test development/sandbox and distribution/production independently with compatible APNs credentials. Rotate a token, simulate 410 with an older/newer invalidation timestamp, replay a webhook, and verify temporary failures retain registrations and accepted claims are not resent.

Additional checks: deleted activity/notification, malformed payload, expired session, incorrect webhook secret, invalid provider credentials, rate limits/timeouts, stopped backend and retry. APNs acceptance, visible delivery, notification tap, read sync and second-device delivery are separate observations; none are claimed complete merely because the build or mocks pass.

## Files and final review status

Created:

- `AfterWork/App/AppDelegate.swift`
- `AfterWork/Core/Notifications/PushModels.swift`
- `AfterWork/Core/Notifications/PushInstallation.swift`
- `AfterWork/Core/Notifications/SigningEntitlements.swift`
- `AfterWork/Core/Notifications/PushNotificationManager.swift`
- `AfterWork/Data/Repositories/PushDeviceRepository.swift`
- `AfterWork/Features/Profile/PushSettingsView.swift`
- `AfterWorkTests/PushNotificationTests.swift`
- `AfterWorkTests/PushUnreadTests.swift`
- `Configuration/AfterWorkPush.entitlements`
- `supabase/config.toml`
- `supabase/functions/send-push-notification/index.ts`
- `supabase/functions/send-push-notification/apns.ts`
- `supabase/functions/send-push-notification/handler.ts`
- `supabase/functions/send-push-notification/store.ts`
- `supabase/functions/send-push-notification/handler_test.ts`
- `supabase/functions/send-push-notification/deno.json`
- `supabase/migrations/20261014120000_stage10_push_notifications.sql`
- `supabase/tests/009_push_notifications.sql`
- `STAGE10.md`

Modified:

- `.gitignore`
- `AfterWork/App/AfterWorkApp.swift`
- `AfterWork/App/RootView.swift`
- `AfterWork/App/MainTabView.swift`
- `AfterWork/Core/Auth/AuthManager.swift`
- `AfterWork/Data/Repositories/NotificationRepository.swift`
- `AfterWork/Features/Notifications/NotificationsViewModel.swift`
- `AfterWork/Features/Profile/ProfileView.swift`
- `README.md`

Deleted: none. Current active signing file, bundle ID/team settings, previously applied migrations, notification creation triggers, local reminder service, Calendar, activities, engagement, comments and photos were not rewritten. The user subsequently authorized committing and pushing `feature/stage-10-remote-push` and merging it into main. Remote deployment and external push configuration remain separate manual steps and were not performed.

Sources checked: [Apple registration](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns), [APS environment](https://developer.apple.com/documentation/bundleresources/entitlements/aps-environment), [APNs provider tokens](https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns), [APNs HTTP API](https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/CommunicatingwithAPNs.html), [Apple code-signature format](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/cs_blobs.h), [Supabase Database Webhooks](https://supabase.com/docs/guides/database/webhooks), [Edge Function authentication](https://supabase.com/docs/guides/functions/auth), [Deno HTTP/2 client](https://docs.deno.com/api/deno/fetch/). Installed SDK signatures and CLI help were also inspected.
