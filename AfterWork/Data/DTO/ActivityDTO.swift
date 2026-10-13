import Foundation

// Database row; intentionally separate from the mock UI model.
nonisolated struct ActivityDTO: Codable, Identifiable, Sendable {
    let id: UUID
    let authorId: UUID
    let categoryId: UUID
    let title: String
    let description: String
    let startAt: Date
    let endAt: Date?
    let locationName: String
    let locationAddress: String?
    let latitude: Double?
    let longitude: Double?
    let maxParticipants: Int?
    let coverImageUrl: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case authorId = "author_id"
        case categoryId = "category_id"
        case title
        case description
        case startAt = "start_at"
        case endAt = "end_at"
        case locationName = "location_name"
        case locationAddress = "location_address"
        case latitude
        case longitude
        case maxParticipants = "max_participants"
        case coverImageUrl = "cover_image_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
