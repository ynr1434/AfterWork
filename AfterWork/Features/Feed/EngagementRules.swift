import Foundation

enum EngagementSwipeAction: Equatable {
    case save, skip
}

enum EngagementRules {
    static let swipeThreshold: CGFloat = 120

    static func swipeAction(for horizontalTranslation: CGFloat) -> EngagementSwipeAction? {
        guard abs(horizontalTranslation) >= swipeThreshold else { return nil }
        return horizontalTranslation > 0 ? .save : .skip
    }

    static func feedActivities(_ activities: [Activity], now: Date = .now) -> [Activity] {
        ActivityDayGroup.upcoming(activities, now: now).filter { !$0.isSkipped }
    }
}
