import Foundation

// Database row; intentionally separate from the mock UI model.
nonisolated struct CommentDTO: Codable, Identifiable, Sendable {
    let id: UUID
    let activityId: UUID
    let authorId: UUID
    let body: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case activityId = "activity_id"
        case authorId = "author_id"
        case body
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
