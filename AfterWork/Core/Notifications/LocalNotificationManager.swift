import Foundation
import UserNotifications

@MainActor
final class LocalNotificationManager {
    enum NotificationError: Error { case denied, past, failed }

    private let center = UNUserNotificationCenter.current()
    private let preferences: ActivityLocalPreferences

    init(preferences: ActivityLocalPreferences = ActivityLocalPreferences()) { self.preferences = preferences }

    var authorizationStatus: UNAuthorizationStatus {
        get async { await center.notificationSettings().authorizationStatus }
    }

    func schedule(activity: Activity, option: ActivityReminderOption) async throws {
        cancel(activityID: activity.id)
        guard option != .none else { preferences.setReminder(.none, for: activity.id); return }
        let date = activity.startsAt.addingTimeInterval(-option.offset)
        guard date > .now else { throw NotificationError.past }
        let status = await authorizationStatus
        if status == .notDetermined {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else { throw NotificationError.denied }
        } else if status == .denied { throw NotificationError.denied }
        let content = UNMutableNotificationContent()
        let timing = option.title.replacingOccurrences(of: " before", with: "")
        content.title = "\(activity.title) starts in \(timing)"
        content.body = activity.locationName.isEmpty ? "Your AfterWork activity is starting soon." : activity.locationName
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let request = UNNotificationRequest(identifier: identifier(for: activity.id), content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
        do { try await center.add(request); preferences.setReminder(option, for: activity.id) }
        catch { throw NotificationError.failed }
    }

    func cancel(activityID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier(for: activityID)])
        preferences.setReminder(.none, for: activityID)
    }

    static func identifier(for activityID: UUID) -> String { "afterwork.activity.\(activityID.uuidString).reminder" }
    func identifier(for activityID: UUID) -> String { Self.identifier(for: activityID) }
}
