import Foundation

// Database row; intentionally separate from the mock UI model.
nonisolated struct ActivityParticipantDTO: Codable, Identifiable, Sendable {
    let id: UUID
    let activityId: UUID
    let userId: UUID
    let status: ParticipantStatus
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case activityId = "activity_id"
        case userId = "user_id"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

nonisolated enum ParticipantStatus: String, Codable, Sendable {
    case interested, going, declined
}
