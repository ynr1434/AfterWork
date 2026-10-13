import Foundation
import Supabase

enum NotificationKind: String, Codable, CaseIterable {
    case mention
    case activityComment
    case unknown

    init(rawValue: String) {
        switch rawValue { case "mention": self = .mention; case "activityComment": self = .activityComment; default: self = .unknown }
    }
}

struct AppNotification: Identifiable, Equatable {
    let id: UUID
    let userID: UUID
    let kind: NotificationKind
    let title: String
    let body: String
    let activityID: UUID?
    let actorUserID: UUID?
    var isRead: Bool
    let createdAt: Date

    init(dto: NotificationDTO) {
        id = dto.id; userID = dto.userId; kind = NotificationKind(rawValue: dto.type)
        title = dto.title; body = dto.body; activityID = dto.activityId; actorUserID = dto.actorUserId
        isRead = dto.isRead; createdAt = dto.createdAt
    }
}

@MainActor
struct NotificationRepository {
    private let client: SupabaseClient
    private let currentUserID: () async throws -> UUID

    init(client: SupabaseClient, currentUserID: (() async throws -> UUID)? = nil) {
        self.client = client
        self.currentUserID = currentUserID ?? { try await client.auth.session.user.id }
    }

    func fetchNotifications() async throws -> [AppNotification] {
        let userID = try await currentUserID()
        do {
            let rows: [NotificationDTO] = try await client.from("notifications").select()
                .eq("user_id", value: userID.uuidString).order("created_at", ascending: false).limit(100).execute().value
            return rows.map(AppNotification.init(dto:))
        } catch { throw DatabaseError.requestFailed }
    }

    func markAsRead(notificationID: UUID) async throws {
        let userID = try await currentUserID()
        struct Update: Encodable { let is_read: Bool }
        do {
            _ = try await client.from("notifications").update(Update(is_read: true))
                .eq("id", value: notificationID.uuidString).eq("user_id", value: userID.uuidString).execute()
        } catch { throw DatabaseError.requestFailed }
    }

    func markAllAsRead() async throws {
        let userID = try await currentUserID()
        struct Update: Encodable { let is_read: Bool }
        do { _ = try await client.from("notifications").update(Update(is_read: true)).eq("user_id", value: userID.uuidString).execute() }
        catch { throw DatabaseError.requestFailed }
    }
}
