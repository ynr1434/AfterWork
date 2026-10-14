import Foundation

enum EngagementSwipeAction: Equatable {
    case save, skip
}

enum EngagementRules {
    static func positionText(index: Int, count: Int) -> String {
        guard count > 0 else { return "No activities" }
        return "\(min(max(0, index) + 1, count)) of \(count)"
    }

    static func nextIndex(after action: FeedView.Action, index: Int, remainingCount: Int, advanceSaved: Bool) -> Int {
        let next = index + (action == .save && advanceSaved ? 1 : 0)
        return min(max(0, next), max(0, remainingCount - 1))
    }

    static let swipeThreshold: CGFloat = 120

    static func swipeAction(for horizontalTranslation: CGFloat) -> EngagementSwipeAction? {
        guard abs(horizontalTranslation) >= swipeThreshold else { return nil }
        return horizontalTranslation > 0 ? .save : .skip
    }

    static func feedActivities(_ activities: [Activity], now: Date = .now) -> [Activity] {
        ActivityDayGroup.upcoming(activities, now: now).filter { !$0.isSkipped }
    }
}
