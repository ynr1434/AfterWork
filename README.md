# AfterWork

AfterWork is an iOS app for coworkers to discover and join activities after work, from volleyball and cinema to coffee and board games.

## Tech stack

- Swift
- SwiftUI
- iOS 17+
- MVVM (feature views are in place; models and view models will be added when needed)
- async/await for future asynchronous work
- Swift Package Manager for future dependencies; no third-party packages currently

## Current stage

Stage 2 — visual foundation and mock activity feed

Current implemented features:

- Five native tabs with independent NavigationStacks
- One prominent activity card in Feed, category filters, and local sample browsing
- Explore rows grouped into Today, Tomorrow, This week, and Coming up when needed
- Six mock activities with relative dates, participant counts, and organizer information
- Category-based SwiftUI cover artwork; no remote images
- Polished Create and Notifications empty states, plus a static sample profile
- Semantic Light/Dark colors and lightweight spacing, radius, and typography tokens
- Reusable cards, rows, chips, avatars, buttons, empty states, and a loading view

Skip cycles through mock cards. Save, Going, and Create activity display preview messages only. Nothing is saved or submitted. No gestures, persistence, networking, or backend integrations are implemented.

## Project structure

```text
AfterWork.xcodeproj/
AfterWork/
├── App/                 # Existing entry point and MainTabView
├── Core/Design/         # AppColors, AppSpacing, AppCornerRadius, AppTypography
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

- Supabase
- Sign in with Apple
- Google Sign In
- EventKit
- Local and remote notifications
- Activity feed, categories, filters, creation, and joining
- Comments
- Mentions
- Photos

These integrations and real product behaviors remain planned. Stage 2 uses local mock data only.
