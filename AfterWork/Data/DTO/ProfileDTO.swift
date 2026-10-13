import Foundation

// Database row; intentionally separate from the mock UI model.
nonisolated struct ProfileDTO: Codable, Identifiable, Sendable {
    let id: UUID
    let email: String?
    let displayName: String
    let avatarUrl: String?
    let department: String?
    let jobTitle: String?
    let interests: [String]?

    var isComplete: Bool {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.count <= 100
    }

    var initials: String {
        let parts = displayName.split(whereSeparator: \.isWhitespace)
        return parts.prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case department
        case jobTitle = "job_title"
        case interests
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
