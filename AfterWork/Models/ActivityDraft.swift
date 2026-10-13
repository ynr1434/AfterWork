import Foundation

/// Form state has no editable author or activity ID. Validation preserves entered text.
nonisolated struct ActivityDraft {
    var title = ""
    var categoryId: UUID?
    var description = ""
    var startsAt = Date.now.addingTimeInterval(3600)
    var hasEnd = false
    var endsAt = Date.now.addingTimeInterval(7200)
    var locationName = ""
    var locationAddress = ""
    var maximumParticipants = ""

    @MainActor
    init(activity: Activity? = nil) {
        guard let activity else { return }
        title = activity.title
        categoryId = activity.categoryId
        description = activity.description
        startsAt = activity.startsAt
        hasEnd = activity.endsAt != nil
        endsAt = activity.endsAt ?? activity.startsAt.addingTimeInterval(3600)
        locationName = activity.locationName
        locationAddress = activity.locationAddress ?? ""
        maximumParticipants = activity.maxParticipants.map(String.init) ?? ""
    }

    var capacity: Int? { Int(maximumParticipants) }
    var validationMessage: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter an activity title." }
        if title.unicodeScalars.count > 160 { return "Use a title of 160 characters or fewer." }
        if categoryId == nil { return "Choose a category." }
        if description.unicodeScalars.count > 10_000 { return "Use a description of 10,000 characters or fewer." }
        if !startsAt.timeIntervalSince1970.isFinite { return "Choose a valid start date." }
        if hasEnd && (!endsAt.timeIntervalSince1970.isFinite || endsAt <= startsAt) {
            return "The end must be later than the start."
        }
        if locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter a location name." }
        if locationName.unicodeScalars.count > 200 { return "Use a location name of 200 characters or fewer." }
        if locationAddress.unicodeScalars.count > 500 { return "Use an address of 500 characters or fewer." }
        if !maximumParticipants.isEmpty {
            guard let capacity, capacity > 0, capacity <= Int(Int32.max),
                  maximumParticipants.allSatisfy({ $0.isASCII && $0.isNumber }) else {
                return "Enter a positive whole-number capacity, or leave it empty."
            }
        }
        return nil
    }
}

nonisolated enum ActivityError: Error, LocalizedError {
    case invalid(String), notFound, notOwner, requestFailed, signInRequired, categoriesUnavailable

    var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        case .notFound: "This activity is no longer available."
        case .notOwner: "Only the organizer can change this activity."
        case .requestFailed: "We couldn't complete the request. Check your connection and try again."
        case .signInRequired: "Please sign in again to continue."
        case .categoriesUnavailable: "We couldn't load activity categories. Please try again."
        }
    }
}

/// No overlapping day buckets, including midnight, DST, and week boundaries.
enum ActivityDayGroup: String, CaseIterable, Identifiable {
    case today = "Today", tomorrow = "Tomorrow", thisWeek = "This Week", later = "Later"
    var id: String { rawValue }

    static func group(for date: Date, now: Date = .now, calendar: Calendar = .current) -> Self {
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) { return .tomorrow }
        if let week = calendar.dateInterval(of: .weekOfYear, for: now), week.contains(date) { return .thisWeek }
        return .later
    }

    static func upcoming(_ activities: [Activity], now: Date = .now) -> [Activity] {
        activities.filter { $0.startsAt >= now }.sorted {
            if $0.startsAt == $1.startsAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.startsAt < $1.startsAt
        }
    }
}
