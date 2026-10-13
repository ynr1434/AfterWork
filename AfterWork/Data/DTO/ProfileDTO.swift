import Foundation

// Database row; intentionally separate from the mock UI model.
nonisolated struct ProfileDTO: Codable, Identifiable, Sendable {
    let id: UUID
    let email: String?
    let displayName: String
    let avatarUrl: String?
    let department: String?
    let jobTitle: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case department
        case jobTitle = "job_title"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
