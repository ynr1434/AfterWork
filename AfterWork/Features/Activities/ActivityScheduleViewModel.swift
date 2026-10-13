import EventKit
import Observation

@MainActor @Observable
final class ActivityScheduleViewModel {
    private(set) var isCalendarAdded = false
    private(set) var reminder: ActivityReminderOption = .none
    private(set) var errorMessage: String?
    private(set) var isBusy = false
    @ObservationIgnored private let calendar: CalendarManager
    @ObservationIgnored private let notifications: LocalNotificationManager
    @ObservationIgnored private let preferences: ActivityLocalPreferences
    @ObservationIgnored private var activityID: UUID?

    init(preferences: ActivityLocalPreferences = ActivityLocalPreferences()) {
        self.preferences = preferences
        calendar = CalendarManager(preferences: preferences)
        notifications = LocalNotificationManager(preferences: preferences)
    }

    func configure(activity: Activity) async {
        activityID = activity.id
        reminder = preferences.reminder(for: activity.id)
        isCalendarAdded = calendar.hasEvent(for: activity.id)
    }

    func addOrUpdateCalendar(activity: Activity) async {
        guard !isBusy else { return }
        isBusy = true; errorMessage = nil
        defer { isBusy = false }
        do { try await calendar.addOrUpdate(activity: activity); isCalendarAdded = true }
        catch let error as CalendarManager.CalendarError { errorMessage = calendarMessage(error) }
        catch { errorMessage = "We couldn't update your calendar. Please try again." }
    }

    func removeCalendar(activityID: UUID) async {
        guard !isBusy else { return }
        isBusy = true; errorMessage = nil
        defer { isBusy = false }
        do { try await calendar.remove(activityID: activityID); isCalendarAdded = false }
        catch let error as CalendarManager.CalendarError { errorMessage = calendarMessage(error) }
        catch { errorMessage = "We couldn't remove the calendar event. Please try again." }
    }

    func setReminder(_ option: ActivityReminderOption, activity: Activity) async {
        guard !isBusy else { return }
        isBusy = true; errorMessage = nil
        defer { isBusy = false }
        do { try await notifications.schedule(activity: activity, option: option); reminder = option }
        catch let error as LocalNotificationManager.NotificationError {
            errorMessage = reminderMessage(error)
        } catch { errorMessage = "We couldn't schedule that reminder. Please try again." }
    }

    func cancelReminder(activityID: UUID) {
        notifications.cancel(activityID: activityID)
        reminder = .none
    }

    func removeAll(activityID: UUID) async {
        cancelReminder(activityID: activityID)
        try? await calendar.remove(activityID: activityID)
        preferences.removeAll(for: activityID)
        isCalendarAdded = false
    }

    func didSave(activity: Activity) async {
        guard isCalendarAdded else { return }
        await addOrUpdateCalendar(activity: activity)
        if reminder != .none { await setReminder(reminder, activity: activity) }
    }

    private func calendarMessage(_ error: CalendarManager.CalendarError) -> String {
        switch error {
        case .denied: "Calendar access is off. Enable it in Settings to add activities."
        case .restricted: "Calendar access is restricted on this device."
        case .noCalendar: "No writable calendar is available on this device."
        case .staleEvent, .saveFailed: "We couldn't update your calendar. Please try again."
        }
    }

    private func reminderMessage(_ error: LocalNotificationManager.NotificationError) -> String {
        switch error {
        case .denied: "Notifications are off. Enable them in Settings to use reminders."
        case .past: "That reminder time has already passed. Choose a later activity or another option."
        case .failed: "We couldn't schedule that reminder. Please try again."
        }
    }
}
