import Foundation
import OSLog
import Supabase

@MainActor
struct ActivityPhotoRepository {
    static let bucketName = "activity-photos"
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AfterWork", category: "ActivityPhotoRepository")
    private let client: SupabaseClient
    private let currentUserID: () async throws -> UUID

    init(client: SupabaseClient, currentUserID: (() async throws -> UUID)? = nil) {
        self.client = client
        self.currentUserID = currentUserID ?? { try await client.auth.session.user.id }
    }

    func fetchPhotos(activityID: UUID) async throws -> [ActivityPhoto] {
        let rows: [ActivityPhotoDTO] = try await client.from("activity_photos")
            .select().eq("activity_id", value: activityID.uuidString)
            .order("created_at").order("id").execute().value
        guard !rows.isEmpty else { return [] }

        let signedURLs = try await client.storage.from(Self.bucketName).createSignedURLs(
            paths: rows.map(\.storagePath), expiresIn: ActivityPhotoRules.signedURLLifetimeSeconds
        )
        var urlsByPath: [String: URL] = [:]
        for result in signedURLs {
            switch result {
            case let .success(path, signedURL): urlsByPath[path] = signedURL
            case let .failure(path, _):
                #if DEBUG
                Self.logger.error("Signed URL unavailable for activity photo, path_hash=\(path.hashValue, privacy: .public)")
                #endif
            }
        }
        return rows.map { ActivityPhoto(dto: $0, displayURL: urlsByPath[$0.storagePath]) }
    }

    func uploadPhoto(activityID: UUID, jpegData: Data) async throws -> ActivityPhoto {
        try ActivityPhotoProcessor.validateProcessedData(jpegData)
        let uploaderID = try await currentUserID()
        let existing: [PhotoID] = try await client.from("activity_photos")
            .select("id").eq("activity_id", value: activityID.uuidString).execute().value
        guard ActivityPhotoRules.canAddPhoto(currentCount: existing.count) else { throw ActivityPhotoError.limitReached }

        let photoID = UUID()
        let path = ActivityPhotoRules.storagePath(activityID: activityID, uploaderID: uploaderID, photoID: photoID)
        do {
            try await client.storage.from(Self.bucketName).upload(
                path, data: jpegData, options: FileOptions(contentType: "image/jpeg", upsert: false)
            )
        } catch {
            await removeUploadedObjectAfterFailure(path: path, activityID: activityID, photoID: photoID)
            if error is CancellationError { throw CancellationError() }
            throw ActivityPhotoError.requestFailed
        }

        do {
            try await client.from("activity_photos").insert(PhotoInsert(
                id: photoID,
                activity_id: activityID,
                uploader_id: uploaderID,
                storage_path: path
            )).execute()
        } catch {
            await removeUploadedObjectAfterFailure(path: path, activityID: activityID, photoID: photoID)
            if error is CancellationError { throw CancellationError() }
            throw ActivityPhotoError.requestFailed
        }

        return ActivityPhoto(dto: ActivityPhotoDTO(
            id: photoID,
            activityId: activityID,
            uploaderId: uploaderID,
            storagePath: path,
            createdAt: .now
        ))
    }

    func deletePhoto(photoID: UUID) async throws {
        let rows: [ActivityPhotoDTO] = try await client.from("activity_photos")
            .select().eq("id", value: photoID.uuidString).limit(1).execute().value
        guard let row = rows.first else { throw ActivityPhotoError.deleteFailed }

        do {
            // Remove the object first. If Storage rejects or is unavailable, keep its metadata visible.
            try await client.storage.from(Self.bucketName).remove(paths: [row.storagePath])
            let deleted: [PhotoID] = try await client.from("activity_photos").delete()
                .eq("id", value: photoID.uuidString).select("id").execute().value
            guard deleted.contains(where: { $0.id == photoID }) else { throw ActivityPhotoError.deleteFailed }
        } catch let error as ActivityPhotoError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            #if DEBUG
            Self.logger.error("Activity photo delete failed, photo_id=\(photoID.uuidString, privacy: .public), error_type=\(String(describing: type(of: error)), privacy: .public)")
            #endif
            throw ActivityPhotoError.deleteFailed
        }
    }

    private func removeUploadedObjectAfterFailure(path: String, activityID: UUID, photoID: UUID) async {
        do {
            try await client.storage.from(Self.bucketName).remove(paths: [path])
        } catch {
            #if DEBUG
            Self.logger.error("Activity photo upload cleanup failed, activity_id=\(activityID.uuidString, privacy: .public), photo_id=\(photoID.uuidString, privacy: .public), error_type=\(String(describing: type(of: error)), privacy: .public)")
            #endif
        }
    }
}

private struct PhotoID: Decodable { let id: UUID }

private struct PhotoInsert: Encodable {
    let id: UUID
    let activity_id: UUID
    let uploader_id: UUID
    let storage_path: String
}
