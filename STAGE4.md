# Stage 4 — authentication, sessions, onboarding and profiles

Branch: `feature/stage-4-auth`, created from fetched `origin/main`. At the implementation review checkpoint, no staging, commit, push, merge, or remote schema/provider changes had been performed. The user subsequently authorized committing and pushing Stage 4. The pre-existing deletion of `Configuration/Config.example.xcconfig` is preserved with the user's authorization. Stage 4 is the scope boundary.

## Architecture and behavior

`AfterWorkApp → RootView` supplies one shared observable `AuthManager`. Its four states are `loading`, `signedOut`, `onboardingRequired`, and `signedIn`. Startup explicitly restores the Supabase session, then fetches the profile using the authenticated UUID. Only a successful fetch returning no row or an incomplete name routes to onboarding. Configuration, restoration, and profile fetch errors keep navigation at a retry screen. Profile requests are cancelled and revision-checked so a late response cannot undo sign-out or a newer save.

`SupabaseManager` continues to own one lazy client. Supabase Swift remains pinned at **2.55.3**. Auth explicitly uses PKCE and SDK default Keychain storage. No tokens are stored in UserDefaults or app-managed storage. SDK auth events update in-memory sessions, handle sign-out/invalidation, and reload profiles for sign-in. Foreground activation checks/refreshes the session; restoration transport failures lock navigation with retry rather than deleting stored credentials. The SDK owns refresh, expiry, persistence, and refresh-token invalidation.

Apple uses the native `SignInWithAppleButton` and AuthenticationServices. Every request generates 32 cryptographically random bytes, sends the SHA-256 nonce to Apple, and sends the raw nonce plus identity token to Supabase `signInWithIdToken`. No nonce is reused or token logged. Cancellation is silent; other errors have safe messages. Apple's first-authorization full name is retained as an onboarding suggestion and saved to Auth metadata when available. If name metadata saving fails, onboarding still permits entering/saving the name. Missing name/email is supported.

Google uses Supabase `signInWithOAuth`, with a native `ASWebAuthenticationSession` launched through the SDK's supported `launchFlow` closure. `OAuthBrowser` retains the browser and presentation anchor and validates the complete callback scheme, host, exact encoded path, absence of userinfo/port/fragment, before returning it to the SDK for PKCE exchange. No Google SDK or client secret is included in the app. The callback is handled by the active browser session; there is deliberately no general `onOpenURL` session importer. Unsolicited cold-launch URLs cannot establish a session. If the app is killed during OAuth, restart sign-in.

Onboarding and editing share `OnboardingView` and `ProfileDraft`. Display name is required (trimmed, 1–100 characters); department/job title are optional free text with department suggestions; multiple optional interests reuse `ActivityCategory` and its database slugs. The form supports keyboard submission, keyboard dismissal, busy/disabled states, validation, save errors, and accessibility selection values. Existing profiles initialize the editing form. Only a successful atomic save permits entry to the tabs.

`ProfileRepository.save` calls `save_my_profile`, whose caller cannot supply a user ID. The function derives `auth.uid()` and upserts on that primary key. Profile fields and interests are saved together; retrying does not create duplicate profiles. Empty optional fields become SQL NULL. Profile displays real name, email when available, initials, department, title, interests, editing, and visible sign-out. Activity summaries remain labeled previews. Sign-out uses SDK `.local` scope (this device), clears in-memory state, cancels outstanding profile reads, and returns to Auth. It never deletes profile/activity data. If server revocation fails after SDK local removal, the signed-out screen reports that limitation.

Feed, Explore, filters, ActivityCard, Create and Notifications placeholders, and mock activities remain unchanged. BackendDebugView remains DEBUG-only and is also reachable before sign-in for troubleshooting. No later-stage features were added.

## Additive database change and security review

Apply only `supabase/migrations/20261013112612_stage4_profile_auth.sql` to the existing development database after already-applied 001/002. Do not rerun or rewrite 001/002. The Stage 4 migration has **not** been applied remotely.

- Adds `profiles.interests text[] NOT NULL DEFAULT '{}'`, bounded to the twelve existing category slugs; rejects NULL members and unknown slugs. This is a small fixed catalog; a relational model can be introduced additively if categories become dynamic later.
- Adds INSERT grants only for `id`, `display_name`, `department`, `job_title`, and `interests`, and an INSERT policy requiring `auth.uid() = id`.
- Grants UPDATE on `interests`; the existing ownership UPDATE policy retains both USING and WITH CHECK.
- Adds a SECURITY INVOKER insert trigger deriving informational email from the authenticated JWT. Client INSERT/UPDATE of email, ID reassignment, and timestamp edits remain prohibited. Existing profile email is preserved on edits; this is not an email-sync feature.
- Adds SECURITY INVOKER `save_my_profile(text,text,text,text[])`. It uses no privileged role and retains RLS/column grants. EXECUTE is revoked from PUBLIC/anon and granted only to authenticated.
- Existing profile SELECT policy permits coworkers to read all profiles, including email and interests. That existing community visibility is preserved; these fields are never authorization claims. No authorization decision uses editable user metadata.
- No RLS is disabled, no service-role key is needed, and no OAuth secrets are bundled. The existing public-key validation remains intact.

The migration and old/new SQL security checks passed in isolated PGlite PostgreSQL with minimal Supabase Auth stubs. This validates syntax, atomic upsert, constraints, grants and ownership behavior, not the remote environment. Remote advisors and remote SQL checks remain manual because no remote database modification was performed.

## Exact manual configuration

The existing local config references `https://ssvgevdfmwljccjodqyg.supabase.co`. The URLs below use that development project; if you intentionally change projects, substitute its actual URL consistently.

### Supabase Dashboard — development

1. Open the **existing** project `ssvgevdfmwljccjodqyg`. In **SQL Editor**, run only the new Stage 4 migration above. Verify `profiles.interests` and `save_my_profile` exist. Use a disposable test project for `supabase/tests/003_profile_auth.sql`; it rolls back its fixtures. Do not run the initial migration again.
2. In **Authentication → Sign In / Providers → Apple**, enable Apple. Add `com.kingz.AfterWork.AfterWork` to the accepted **Client IDs** (the native App ID / identity-token audience), retaining any other legitimate IDs. Keep nonce verification enabled. Native-only ID-token authentication does not need an Apple web client secret, Services ID, or signing `.p8` key in this iOS app. Save.
3. In **Authentication → Sign In / Providers → Google**, enable Google. Enter the **Web application OAuth Client ID** and **Client Secret** created below. Store the secret in Supabase only. Keep nonce/security defaults enabled. Save.
4. In **Authentication → URL Configuration → Redirect URLs**, add exactly:
   `com.kingz.AfterWork.AfterWork://auth/callback`
   Avoid wildcard redirects. Preserve the project's legitimate Site URL; this native app explicitly passes its redirect URL and does not rely on Site URL fallback.
5. Verify the Google provider's displayed server callback is:
   `https://ssvgevdfmwljccjodqyg.supabase.co/auth/v1/callback`
6. Run real Apple and Google sign-in on a correctly signed app, then check **Authentication → Users**. Complete onboarding and check that `profiles.id` equals the Auth UUID, fields/interests match, and reopening the app restores the same user. Edit/clear fields, sign out/reopen, and test cancellation/offline retry. Verify a second user cannot write the first user's profile/interests. Do not disable RLS to fix configuration errors.

### Apple Developer and Xcode — development

1. Use a paid Apple Developer team with an explicit App ID **`com.kingz.AfterWork.AfterWork`**, matching the existing Debug and Release bundle identifier exactly. In **Certificates, Identifiers & Profiles → Identifiers → App IDs**, enable **Sign in with Apple** for this identifier, completing Apple's grouping/primary App ID configuration if required by your account.
2. In Xcode select the **AfterWork** target → **Signing & Capabilities**, select your actual team and use automatic signing or a development provisioning profile that contains Sign in with Apple. No team identifier was invented in source.
3. The project now records the capability, sets `CODE_SIGN_ENTITLEMENTS = Configuration/AfterWork.entitlements`, and includes `com.apple.developer.applesignin = [Default]`. Confirm Xcode recognizes the entitlement and refresh/regenerate provisioning after enabling it remotely.
4. The Info.plist URL Type is already wired with scheme `$(PRODUCT_BUNDLE_IDENTIFIER)`, expanding to **`com.kingz.AfterWork.AfterWork`**. Its callback is **`com.kingz.AfterWork.AfterWork://auth/callback`**. Do not add Google's reversed-client-ID scheme; this implementation uses hosted Supabase OAuth, not Google's native SDK.
5. Keep the existing ignored `Configuration/Config.xcconfig`. If creating one on a fresh checkout, enter only public client config:
   ```xcconfig
   SUPABASE_URL = https:/$()/ssvgevdfmwljccjodqyg.supabase.co
   SUPABASE_ANON_KEY = YOUR_PUBLIC_PUBLISHABLE_KEY
   ```
   The `$()` escape is required for xcconfig URLs. Do not embed provider secrets or privileged keys.
6. Test Apple on a real device signed by the authorized team, with a valid Apple account and the capability enabled. Simulator compilation does not verify Apple authorization/provisioning.

### Google Cloud Console — development

1. Open the intended Google Cloud project → **Google Auth Platform** (or **APIs & Services → OAuth consent screen**). Configure **Branding** with AfterWork's app name, support email, and developer contact. Configure **Audience** as Internal only if the intended workforce belongs to that Workspace organization; otherwise External.
2. For External/testing mode, add the specific developer accounts under **Test users**. Configure basic identity scopes (`openid`, email, profile); no Calendar or other Google API access is required.
3. In **Clients → Create client**, choose **Web application** because Supabase handles Google's server callback. Add this **Authorized redirect URI** exactly:
   `https://ssvgevdfmwljccjodqyg.supabase.co/auth/v1/callback`
   Do not enter the app's custom scheme as Google's authorized redirect URI. This native browser OAuth implementation has no JavaScript frontend requiring a JavaScript origin.
4. Copy that Web client ID and secret into the Supabase Google provider settings. Never put the secret in Swift, xcconfig, assets, or Info.plist. No separate iOS OAuth client is required for this hosted-browser flow.
5. If operating a locally hosted Supabase stack later, configure its own OAuth client callback `http://127.0.0.1:54321/auth/v1/callback`; the current app is configured for the hosted development project, not that local stack.

### Distribution requirements

- Select the production Apple team/App ID, enable the same capability, and use a valid distribution provisioning profile. Validate entitlements in a signed device archive/TestFlight build. If changing bundle ID, update `AuthCallback.url`, Supabase accepted Apple client IDs/redirect list, and the URL Type consistently.
- Use the intended production Supabase project, apply the additive migration through a reviewed deployment workflow, and configure its own Google callback/client secrets and redirect allowlist. Never ship development test-user assumptions.
- Publish Google's consent configuration for the intended audience and complete any branding/domain/privacy-policy verification Google requires. Configure truthful app name, support contacts, privacy policy and terms links. Remove unneeded development redirects from production settings.
- This app uses native Apple ID-token exchange only. If Apple **web OAuth** is added later, separately create a Services ID linked to the App ID, register the Supabase domain and HTTPS callback, configure the signing key/client secret server-side, and rotate the Apple web secret at least every six months. Those web settings are not prerequisites for this native-only Stage 4 implementation.

Provider settings, signing-team permissions, and live OAuth have **not** been verified or completed externally.

References: [Supabase native Apple guidance](https://supabase.com/docs/guides/auth/social-login/auth-apple), [Google provider setup](https://supabase.com/docs/guides/auth/social-login/auth-google), [Swift OAuth/browser API](https://supabase.com/docs/reference/swift/auth-signinwithoauth), [redirect allowlists](https://supabase.com/docs/guides/auth/redirect-urls), [Google button branding and official logo](https://developers.google.com/identity/branding-guidelines).

## Validation and reproducible commands

- **Debug:** simulator build succeeded, including the app-hosted test build on iPhone 17 Pro / iOS 26.5.
- **Release:** simulator build succeeded. Device/archive signing was not tested.
- **Warnings:** no Swift warnings introduced. Xcode emits its AppIntents metadata-skipped warning because this app does not use AppIntents.
- **XCTest:** six AuthManager tests pass: missing session → Auth; existing profile → tabs; absent/incomplete profile → onboarding; profile network failure → blocked loading and successful retry; restoration transport failure → blocked loading; late profile completion cannot undo sign-out/session removal.
- **Standalone Swift:** Stage 3 configuration/all-eight-DTO checks pass; Stage 4 completeness, name validation, optional-field normalization, interest mapping, session-dependent routing, and exact callback rejection checks pass.
- **SQL:** original 001/002 checks pass both before and after the additive migration; new 003 checks pass. Tests include own insert/upsert, no duplicates, clearing optional fields, missing email, failed-save atomicity, invalid interests, cross-user insert/update denial, client email/ID protection, anonymous denial and retained RLS/invoker behavior.
- **Local UI:** signed-out auth screen launched; Light/Dark appearances inspected; DEBUG connection checker navigation verified. The live checker invocation was interrupted by the UI tool disconnecting, so a new connection result is not claimed.
- **Not end-to-end verified:** live Apple/Google authorization and cancellation, external redirect configuration, real session persistence across relaunch, remote profile/onboarding/edit saves, and live server logout/revocation. These require the manual provider/migration setup and signed-device checks above. No fake signed-in bypass was added.

```sh
xcodebuild -project AfterWork.xcodeproj -scheme AfterWork -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' CODE_SIGNING_ALLOWED=NO test
xcodebuild -project AfterWork.xcodeproj -scheme AfterWork -configuration Release \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

xcrun swiftc -parse-as-library -module-cache-path /tmp/AfterWork-Stage4-test-cache \
  AfterWork/Core/Auth/AuthState.swift AfterWork/Data/DTO/ProfileDTO.swift \
  Tests/Stage4AuthChecks.swift -o /tmp/AfterWork-Stage4-checks
/tmp/AfterWork-Stage4-checks
```

The Stage 3 standalone command is in README. Run SQL checks as postgres in an isolated Supabase test project, or use an isolated PGlite runtime with roles `anon`, `authenticated`, `service_role BYPASSRLS`, an `auth.users(id uuid)` table, and `auth.uid()`/`auth.jwt()` helpers reading `request.jwt.claim.sub`/`request.jwt.claims`. The PGlite validation used those stubs; it did not connect to Supabase.

## File report and Git status

Created:

- `AfterWork/App/RootView.swift`
- `AfterWork/Core/Auth/AuthManager.swift`
- `AfterWork/Core/Auth/AuthState.swift`
- `AfterWork/Core/Auth/AuthError.swift`
- `AfterWork/Core/Auth/OAuthBrowser.swift`
- `AfterWork/Features/Auth/AuthView.swift`
- `AfterWork/Features/Onboarding/OnboardingView.swift`
- `AfterWork/Assets.xcassets/GoogleG.imageset/Contents.json`
- `AfterWork/Assets.xcassets/GoogleG.imageset/g-logo.png` (official Google asset)
- `Configuration/AfterWork.entitlements`
- `AfterWorkTests/AuthManagerTests.swift`
- `Tests/Stage4AuthChecks.swift`
- `AfterWork.xcodeproj/xcshareddata/xcschemes/AfterWork.xcscheme`
- `supabase/migrations/20261013112612_stage4_profile_auth.sql`
- `supabase/tests/003_profile_auth.sql`
- `STAGE4.md`

Modified:

- `AfterWork.xcodeproj/project.pbxproj` (capability, entitlement and test target)
- `AfterWork/App/AfterWorkApp.swift`
- `AfterWork/App/MainTabView.swift` (preview environment only)
- `AfterWork/Core/Supabase/SupabaseManager.swift`
- `AfterWork/Data/DTO/ProfileDTO.swift`
- `AfterWork/Data/Repositories/ProfileRepository.swift`
- `AfterWork/Features/Profile/ProfileView.swift`
- `AfterWork/Models/ActivityCategory.swift` (database slug mapping)
- `Configuration/Info.plist`
- `README.md`
- `.gitignore` (exclude local Xcode window state)

Deleted: only the **pre-existing, user-authorized** deletion of `Configuration/Config.example.xcconfig`; Stage 4 deleted no tracked files.

Stage 4 is on `feature/stage-4-auth`; the user subsequently authorized committing and pushing this branch. Review/apply the migration and provider settings before real end-to-end testing. Remote migration/provider setup is separate from publishing the source changes.
