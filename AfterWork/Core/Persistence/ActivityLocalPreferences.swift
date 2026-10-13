import Foundation

/// Device-local state for calendar events and reminders created by AfterWork.
struct ActivityLocalPreferences {
    private let defaults: UserDefaults
    private let eventKey = "afterwork.calendar.events"
    private let reminderKey = "afterwork.activity.reminders"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func eventIdentifier(for activityID: UUID) -> String? {
        (defaults.dictionary(forKey: eventKey) as? [String: String])?[activityID.uuidString]
    }

    func setEventIdentifier(_ identifier: String?, for activityID: UUID) {
        var values = defaults.dictionary(forKey: eventKey) as? [String: String] ?? [:]
        if let identifier { values[activityID.uuidString] = identifier } else { values.removeValue(forKey: activityID.uuidString) }
        defaults.set(values, forKey: eventKey)
    }

    func reminder(for activityID: UUID) -> ActivityReminderOption {
        let values = defaults.dictionary(forKey: reminderKey) as? [String: Int] ?? [:]
        return ActivityReminderOption(rawValue: values[activityID.uuidString] ?? 0) ?? .none
    }

    func setReminder(_ option: ActivityReminderOption, for activityID: UUID) {
        var values = defaults.dictionary(forKey: reminderKey) as? [String: Int] ?? [:]
        if option == .none { values.removeValue(forKey: activityID.uuidString) }
        else { values[activityID.uuidString] = option.rawValue }
        defaults.set(values, forKey: reminderKey)
    }

    func removeAll(for activityID: UUID) {
        setEventIdentifier(nil, for: activityID)
        setReminder(.none, for: activityID)
    }
}

enum ActivityReminderOption: Int, CaseIterable, Identifiable, Codable {
    case none = 0
    case tenMinutes = 10
    case thirtyMinutes = 30
    case oneHour = 60

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .none: "None"
        case .tenMinutes: "10 minutes before"
        case .thirtyMinutes: "30 minutes before"
        case .oneHour: "1 hour before"
        }
    }
    var offset: TimeInterval { TimeInterval(rawValue * 60) }
}
