# Stage 15 — Final MVP UI/UX Polish

## Scope and repository state

This work continues the colleague's Stage 15 baseline (`1ac5d9d`) on `feature/stage-15-mvp-polish`, based on `main` at `fe90b5a` (Stage 10). Stages 11–14 remain intentionally skipped. This is a local, uncommitted review snapshot; no database, Supabase project, signing configuration, or deployment target was changed.

The pre-existing Stage 15 branch introduced the design and screen polish inventoried below. This continuation adds a separate mock place-discovery Feed, narrowly scoped Explore/Details engagement consistency, Create Activity accessibility/keyboard refinements, regression coverage, and documentation.

## Implementation audit

- **Design system and components:** the branch centralizes colors, typography, spacing, and surfaces through existing design tokens and reusable button, card, inline-message, activity-date, empty-state, avatar, and cover components. Shared styling favors adaptive system colors and restrained surfaces.
- **Navigation and tab bar:** retained the five existing tabs and navigation architecture. Screen state remains scoped to the signed-in account; the main tab hierarchy is keyed by the user identity. No tab or navigation feature was added.
- **Feed and activity cards:** the Feed is a separate set of 12 local Almaty place ideas, not an activity list copied from Explore. Cards use local photos, swipe left to pass and right to save; saved places open a detail page with a Create Activity action that pre-fills the venue and area. These suggestions are not live venue status or availability, and they never trigger Supabase activity or engagement writes. Explore retains the backend activity list and its existing actions.
- **Explore:** polished existing category grouping, activity rows, loading/empty/error presentation, and navigation without adding full search, maps, recommendations, or new filtering.
- **Create Activity:** refined form sectioning, validation and progress feedback, date/category inputs, and large-text behavior. The visible keyboard “Done” toolbar control was removed; interactive scroll dismissal and native field submit behavior remain. At accessibility text sizes the navigation title uses inline presentation and category selection uses a wrapping navigation row.
- **Activity Details:** a large category-art hero, clear time/location rows, organizer and participant cards, a fixed Save/Join action bar, calendar/reminder actions, photos, and discussion. Pull-to-refresh and Retry share one reload path for activity, engagement, schedule, photos, and comments; engagement responses are applied only to the matching activity. A leave-action hint is available to assistive technologies.
- **Photos:** preserved the private bucket, signed/authenticated image access, upload/delete authorization, and existing photo limit. The branch improves gallery presentation, placeholders, fullscreen behavior, and cleanup integration; no storage policy or migration was edited in this continuation.
- **Comments and mentions:** retained existing comment ownership and mention behavior while improving composer, empty/loading presentation, and accessibility. No messaging feature was added.
- **Notifications and push:** refined read/unread hierarchy, type presentation, empty/loading state, navigation and unread badge. Stage 10 APNs architecture was not changed.
- **Profile and onboarding:** improved profile/onboarding presentation, account-specific state handling, accessible selection feedback, and empty/error states while retaining the current profile feature set.
- **Authentication:** polished welcome and provider button presentation. OAuth callbacks, providers, Bundle Identifier, credentials, Apple entitlement, and signing configuration were not changed. Google/Apple sign-in were not revalidated in this Stage 15 run.
- **Loading, empty, and error states:** reused inline and full-screen states, progress-aware buttons, retry actions where already supported, and photo placeholders. This work did not introduce generalized networking/retry infrastructure.
- **Buttons, interaction, animation:** improved touch/accessibility affordances, disabled/progress semantics, confirmation flows and action feedback. Feed carousel browsing has Previous/Next buttons as well as horizontal swipes; no mock card invokes real engagement actions. Animations respect Reduce Motion; no animation framework was introduced.
- **Dark mode and accessibility:** inspected light and dark simulator screens at standard and accessibility text sizes. The large-text Create Activity layout issue observed during QA was corrected. Controls use labels/hints and minimum-height affordances in the audited flows. This is not a complete VoiceOver audit; physical-device and full workflow review remain necessary.
- **Keyboard and dates:** Create Activity uses interactive native scroll dismissal and submit labels. Existing date presentation remains locale-aware through shared date formatting; stored timestamps and calendar behavior were not changed.
- **Performance:** no caching framework or broad repository rewrite was introduced. Refresh handling avoids layering stale detail engagement values over a separately refreshed activity list.

## Changes made in this continuation

1. `AlmatyPlaceSuggestion.swift` adds 12 static venue cards; the Feed presents them in a small navigable carousel with group-planning copy and no backend side effects.
2. `ActivityListViewModel` keeps confirmed engagement state per model instance after activity-list refreshes while accepting fresh backend participant counts. This remains relevant to Explore/Details shared state. Deleted activities discard their cached state.
3. `ActivityDetailsView` consolidates initial loading, refresh, and retry into one reload operation and guards engagement application by activity ID.
4. `CreateActivityView` improves large-text navigation/category layout and retains native keyboard dismissal without a redundant Done button.
5. Tests verify the 12 unique mock suggestions, shared engagement state across refresh, unsave/leave updates, fresh participant counts, and model-instance isolation. An existing photo-access test runs async on the main actor; its assertions remain intact. This addressed a Swift runtime deallocation crash in the prior synchronous test invocation.

## Validation

- **Debug build:** passed using Xcode Simulator destination iPhone 17 Pro / iOS 26.1.
- **Release build:** passed using Xcode Simulator destination iPhone 17 Pro / iOS 26.1.
- **XCTest:** 82 tests passed, 0 failures after replacing obsolete Feed-action tests with mock-catalog coverage. There is no UI test target or test plan in the project, so no UI test suite was available.
- **`git diff --check`:** passed after the implementation; rerun before review/commit.
- **Visual QA actually performed:** captured and inspected the iPhone 17 Pro light-mode sign-in screen; iPhone 16e dark-mode tabs at accessibility text sizes; the iPhone 16e Feed at standard text size after restoring the simulator; and an existing authenticated Activity Details/photo/fullscreen flow on the iPhone 16e simulator. An existing authenticated session was already present; no login credentials were handled. The activity was viewed without modifying backend data.
- **Not verified:** Google and Apple provider authentication, APNs delivery, physical devices, landscape, complete VoiceOver journeys, a second-account authorization matrix, or all mutation workflows end-to-end. No live Supabase writes were made.

## Supported devices and manual beta checklist

The app retains the existing iOS 17.0 deployment target and iPhone-first SwiftUI layouts; simulator build/visual checks used iOS 26.1. The project has no dedicated iPad redesign. Before beta distribution, manually check on a small, standard, and large physical iPhone in light/dark mode and larger Dynamic Type, including:

1. Google and Apple login, onboarding, session restoration, and logout.
2. Feed's 12 place ideas and browsing controls, then Explore loading/refresh and real activity engagement.
3. Create, edit, delete, duplicate-submit prevention, and validation for an activity.
4. Join/leave, capacity, participants, and account switching.
5. Comment create/edit/delete, mention selection, notification navigation/read state.
6. Private photo upload, signed loading, fullscreen paging, deletion, and activity cleanup.
7. Calendar authorization/reminders, notification permission and APNs delivery on correctly provisioned hardware.
8. Keyboard/large-text behavior, VoiceOver labels and focus order, Reduce Motion, offline/error/retry states, safe areas, and long titles/comments.

## MVP and release readiness audit

No newly reproduced core-flow or data-isolation blocker was found in this Stage 15 pass. This is not an end-to-end sign-off for authentication, APNs, or all backend mutations; those require the manual checks above.

**App Review prerequisites/blockers to resolve before submission:**

- The app supports user-generated comments and activity photos, but this code audit found no in-app objectionable-content filtering, content/user reporting flow, user blocking flow, or published contact information. Apple requires these safeguards for apps with user-generated content/social networking. Add and verify an operational moderation/report/block path and provide contact information before submission. [Apple App Review Guidelines, section 1.2](https://developer.apple.com/app-store/review/guidelines/uk/)
- The app supports account creation but no in-app account-deletion path was found. Apple requires users to be able to initiate deletion within the app and associated user-generated content must be handled. Resolve before submission. [Apple account deletion requirement](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion)
- Complete App Store metadata and privacy disclosures, provide a working privacy policy and support contact, and provide App Review with a usable test account or review path for gated features.
- Validate Apple Developer provisioning/capabilities and push entitlements with the release team. Do not change local signing as part of this Stage 15 work.
- Confirm privacy labels, third-party SDK disclosures, and required-reason API declarations against the final archive and current Apple requirements.

Maps/GPS, smart discovery, expanded profiles, and advanced moderation tooling remain intentionally outside this MVP scope. The existing moderation gap above is a compliance concern, not permission to start Stage 14 implicitly.

## Git and security boundaries

- Branch: `feature/stage-15-mvp-polish`.
- No files were deleted.
- No migration, SQL test, Supabase credential/configuration, OAuth setting, signing entitlement, project signing setting, or APNs backend file was changed by this continuation.
- No secrets were printed or added.
- Nothing was staged, committed, pushed, merged, or deployed. Stop here for review and approval.
