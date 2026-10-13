import Foundation

nonisolated struct ActivityUserActionDTO: Codable, Identifiable, Sendable {
    let id: UUID
    let activityId: UUID
    let userId: UUID
    let isSaved: Bool
    let isSkipped: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case activityId = "activity_id"
        case userId = "user_id"
        case isSaved = "is_saved"
        case isSkipped = "is_skipped"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

nonisolated struct ParticipantDTO: Decodable, Identifiable, Sendable {
    struct Profile: Decodable, Sendable {
        let id: UUID
        let displayName: String
        let jobTitle: String?
        let department: String?

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
            case jobTitle = "job_title"
            case department
        }
    }

    let id: UUID
    let activityId: UUID
    let userId: UUID
    let status: ParticipantStatus
    let profile: Profile?

    enum CodingKeys: String, CodingKey {
        case id
        case activityId = "activity_id"
        case userId = "user_id"
        case status
        case profile
    }

    var initials: String {
        profile?.displayName.split(whereSeparator: \.isWhitespace).prefix(2)
            .compactMap { $0.first.map(String.init) }.joined().uppercased() ?? ""
    }
}
