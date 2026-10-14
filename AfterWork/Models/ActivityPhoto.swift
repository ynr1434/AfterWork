import Foundation

struct ActivityPhoto: Identifiable, Equatable, Sendable {
    let id: UUID
    let activityId: UUID
    let uploaderId: UUID
    let storagePath: String
    let createdAt: Date
    var displayURL: URL?

    init(dto: ActivityPhotoDTO, displayURL: URL? = nil) {
        id = dto.id
        activityId = dto.activityId
        uploaderId = dto.uploaderId
        storagePath = dto.storagePath
        createdAt = dto.createdAt
        self.displayURL = displayURL
    }
}

enum ActivityPhotoRules {
    static let maximumPhotoCount = 10
    static let maximumUploadBytes = 5 * 1024 * 1024
    static let maximumLongEdge = 2_200
    static let signedURLLifetimeSeconds = 900

    static func canAddPhoto(currentCount: Int) -> Bool {
        currentCount < maximumPhotoCount
    }

    static func canUpload(activityAuthorID: UUID, currentUserID: UUID?, isGoing: Bool) -> Bool {
        guard let currentUserID else { return false }
        return activityAuthorID == currentUserID || isGoing
    }

    static func canDelete(uploaderID: UUID, activityAuthorID: UUID, currentUserID: UUID?) -> Bool {
        guard let currentUserID else { return false }
        return uploaderID == currentUserID || activityAuthorID == currentUserID
    }

    static func storagePath(activityID: UUID, uploaderID: UUID, photoID: UUID) -> String {
        "activities/\(activityID.uuidString.lowercased())/\(uploaderID.uuidString.lowercased())/\(photoID.uuidString.lowercased()).jpg"
    }
}

enum ActivityPhotoError: Error, LocalizedError, Equatable {
    case invalidImage
    case tooLarge
    case limitReached
    case notAllowed
    case requestFailed
    case deleteFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage: "This image couldn't be prepared. Choose another photo and try again."
        case .tooLarge: "This photo is too large to upload. Choose a smaller image."
        case .limitReached: "This activity already has the maximum of 10 photos."
        case .notAllowed: "Only people going to this activity can add photos."
        case .requestFailed: "We couldn't load or upload activity photos. Please try again."
        case .deleteFailed: "We couldn't delete this photo. Please try again."
        }
    }
}
