import Foundation
import Observation

@MainActor @Observable
final class NotificationsViewModel {
    private(set) var notifications: [AppNotification] = []
    private(set) var isMarkingAll = false
    private var markingIDs = Set<UUID>()
    private(set) var isLoading = false
    var errorMessage: String?
    private var reloadRequested = false
    private var readRevision = 0
    private let repository: NotificationRepository?

    private(set) var unreadCount = 0

    init(repository: NotificationRepository? = nil) {
        self.repository = repository ?? (try? NotificationRepository(client: SupabaseManager.shared.client))
    }

    func load() async {
        guard !isLoading else { reloadRequested = true; return }
        guard let repository else { errorMessage = DatabaseError.notConfigured.localizedDescription; return }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        repeat {
            reloadRequested = false
            let revision = readRevision
            do {
                async let rows = repository.fetchNotifications()
                async let count = repository.fetchUnreadCount()
                let result = try await (rows,count)
                guard !Task.isCancelled else { return }
                guard revision == readRevision else { reloadRequested = true; continue }
                notifications = result.0; unreadCount = result.1
                errorMessage = nil
            } catch { errorMessage = "We couldn't load notifications. Please try again." }
        } while reloadRequested && !Task.isCancelled
    }

    func markRead(_ notification: AppNotification) async {
        guard !notification.isRead, !isMarkingAll, !markingIDs.contains(notification.id), let repository else { return }
        markingIDs.insert(notification.id)
        defer { markingIDs.remove(notification.id) }
        do {
            try await repository.markAsRead(notificationID: notification.id)
            readRevision += 1
            if isLoading { reloadRequested = true }
            errorMessage = nil
            if let index = notifications.firstIndex(where: { $0.id == notification.id }) { notifications[index].isRead = true }
            unreadCount = try await repository.fetchUnreadCount()
        } catch { errorMessage = "We couldn't update that notification." }
    }

    func markAllRead() async {
        guard unreadCount > 0, !isMarkingAll, markingIDs.isEmpty, let repository else { return }
        isMarkingAll = true
        defer { isMarkingAll = false }
        do { try await repository.markAllAsRead(); readRevision += 1; if isLoading { reloadRequested = true }; errorMessage = nil; unreadCount = try await repository.fetchUnreadCount(); notifications = notifications.map { var copy = $0; copy.isRead = true; return copy } }
        catch { errorMessage = "We couldn't update notifications." }
    }
}
