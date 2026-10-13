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

Stage 1 — project foundation

Current implemented features:

- Base architecture with feature-oriented folders
- TabView with Feed, Explore, Create, Notifications, and Profile
- Placeholder feature screens, each with its own NavigationStack
- Basic design tokens: AppSpacing, AppCornerRadius, AppTypography
- Reusable EmptyStateView with an SF Symbol, title, and optional subtitle

## Project structure

```text
AfterWork.xcodeproj/
AfterWork/
├── App/
│   ├── AfterWorkApp.swift
│   └── MainTabView.swift
├── Core/
│   └── Design/
│       ├── AppSpacing.swift
│       ├── AppCornerRadius.swift
│       └── AppTypography.swift
├── Components/
│   └── EmptyStateView.swift
├── Features/
│   ├── Feed/FeedView.swift
│   ├── Explore/ExploreView.swift
│   ├── CreateActivity/CreateActivityView.swift
│   ├── Notifications/NotificationsView.swift
│   └── Profile/ProfileView.swift
└── Resources/
    └── Assets.xcassets/
```

Models is a reserved logical area for future domain types. No empty Models folder or placeholder models are needed in Stage 1. Views contain only presentation; feature view models will own state and behavior when those features are implemented.

The existing Xcode project uses a synchronized folder group, so files under AfterWork are discovered automatically.

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

These features are planned only and are not implemented in Stage 1.
