import Foundation
import Observation

@MainActor @Observable
final class NotificationsViewModel {
    private(set) var notifications: [AppNotification] = []
    private(set) var isLoading = false
    var errorMessage: String?
    private let repository: NotificationRepository?

    var unreadCount: Int { notifications.reduce(into: 0) { if !$1.isRead { $0 += 1 } } }

    init(repository: NotificationRepository? = nil) {
        self.repository = repository ?? (try? NotificationRepository(client: SupabaseManager.shared.client))
    }

    func load() async {
        guard !isLoading else { return }
        guard let repository else { errorMessage = DatabaseError.notConfigured.localizedDescription; return }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do { notifications = try await repository.fetchNotifications() }
        catch { errorMessage = "We couldn't load notifications. Please try again." }
    }

    func markRead(_ notification: AppNotification) async {
        guard !notification.isRead, let repository else { return }
        do {
            try await repository.markAsRead(notificationID: notification.id)
            if let index = notifications.firstIndex(where: { $0.id == notification.id }) { notifications[index].isRead = true }
        } catch { errorMessage = "We couldn't update that notification." }
    }

    func markAllRead() async {
        guard unreadCount > 0, let repository else { return }
        do { try await repository.markAllAsRead(); notifications = notifications.map { var copy = $0; copy.isRead = true; return copy } }
        catch { errorMessage = "We couldn't update notifications." }
    }
}
