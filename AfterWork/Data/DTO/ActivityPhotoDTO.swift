import Foundation

// Database row; intentionally separate from the mock UI model.
nonisolated struct ActivityPhotoDTO: Codable, Identifiable, Sendable {
    let id: UUID
    let activityId: UUID
    let uploaderId: UUID
    let storagePath: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case activityId = "activity_id"
        case uploaderId = "uploader_id"
        case storagePath = "storage_path"
        case createdAt = "created_at"
    }
}
