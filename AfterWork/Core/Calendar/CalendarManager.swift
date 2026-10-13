import EventKit
import Foundation

@MainActor
final class CalendarManager {
    enum CalendarError: Error { case denied, restricted, noCalendar, staleEvent, saveFailed }

    private let store = EKEventStore()
    private let preferences: ActivityLocalPreferences

    init(preferences: ActivityLocalPreferences = ActivityLocalPreferences()) {
        self.preferences = preferences
    }

    var authorizationStatus: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }

    func requestAccessIfNeeded() async throws {
        switch authorizationStatus {
        case .fullAccess: return
        case .denied: throw CalendarError.denied
        case .restricted: throw CalendarError.restricted
        case .notDetermined:
            guard try await store.requestFullAccessToEvents() else { throw CalendarError.denied }
        @unknown default: throw CalendarError.denied
        }
    }

    func addOrUpdate(activity: Activity) async throws {
        try await requestAccessIfNeeded()
        guard let calendar = store.defaultCalendarForNewEvents else { throw CalendarError.noCalendar }
        let event: EKEvent
        if let identifier = preferences.eventIdentifier(for: activity.id), let existing = store.event(withIdentifier: identifier) {
            event = existing
        } else {
            if preferences.eventIdentifier(for: activity.id) != nil { preferences.setEventIdentifier(nil, for: activity.id) }
            event = EKEvent(eventStore: store)
            event.calendar = calendar
        }
        event.title = activity.title
        event.startDate = activity.startsAt
        event.endDate = activity.endsAt ?? activity.startsAt.addingTimeInterval(3600)
        event.location = [activity.locationName, activity.locationAddress].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        event.notes = activity.description.isEmpty ? "Added by AfterWork." : "(activity.description)\n\nAdded by AfterWork."
        do {
            try store.save(event, span: .thisEvent, commit: true)
            preferences.setEventIdentifier(event.eventIdentifier, for: activity.id)
        } catch { throw CalendarError.saveFailed }
    }

    func remove(activityID: UUID) async throws {
        try await requestAccessIfNeeded()
        guard let identifier = preferences.eventIdentifier(for: activityID) else { return }
        if let event = store.event(withIdentifier: identifier) {
            do { try store.remove(event, span: .thisEvent, commit: true) } catch { throw CalendarError.saveFailed }
        }
        preferences.setEventIdentifier(nil, for: activityID)
    }

    func hasEvent(for activityID: UUID) -> Bool {
        guard let identifier = preferences.eventIdentifier(for: activityID) else { return false }
        if store.event(withIdentifier: identifier) != nil { return true }
        preferences.setEventIdentifier(nil, for: activityID)
        return false
    }
}
