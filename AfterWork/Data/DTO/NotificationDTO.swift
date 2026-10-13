import Foundation

// Database row; intentionally separate from the mock UI model.
nonisolated struct NotificationDTO: Codable, Identifiable, Sendable {
    let id: UUID
    let userId: UUID
    let type: String
    let title: String
    let body: String
    let activityId: UUID?
    let actorUserId: UUID?
    let isRead: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case type
        case title
        case body
        case activityId = "activity_id"
        case actorUserId = "actor_user_id"
        case isRead = "is_read"
        case createdAt = "created_at"
    }
}
