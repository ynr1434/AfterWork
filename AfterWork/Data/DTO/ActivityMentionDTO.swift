import Foundation

// Database row; intentionally separate from the mock UI model.
nonisolated struct ActivityMentionDTO: Codable, Identifiable, Sendable {
    let id: UUID
    let activityId: UUID
    let commentId: UUID?
    let mentionedUserId: UUID
    let mentionedByUserId: UUID
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case activityId = "activity_id"
        case commentId = "comment_id"
        case mentionedUserId = "mentioned_user_id"
        case mentionedByUserId = "mentioned_by_user_id"
        case createdAt = "created_at"
    }
}
