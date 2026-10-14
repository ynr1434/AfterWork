import Foundation
import Observation
import PhotosUI
import SwiftUI

@MainActor @Observable
final class ActivityPhotosViewModel {
    private(set) var photos: [ActivityPhoto] = []
    private(set) var isLoading = false
    private(set) var isUploading = false
    private(set) var deletingPhotoID: UUID?
    private(set) var errorMessage: String?
    private(set) var currentUserID: UUID?
    private(set) var activityAuthorID: UUID?
    private(set) var canUpload = false
    @ObservationIgnored private let repository: ActivityPhotoRepository?

    init(repository: ActivityPhotoRepository? = nil) {
        self.repository = repository ?? (try? ActivityPhotoRepository(client: SupabaseManager.shared.client))
    }

    func updateAccess(activity: Activity, currentUserID: UUID?) {
        self.currentUserID = currentUserID
        activityAuthorID = activity.authorId
        canUpload = ActivityPhotoRules.canUpload(
            activityAuthorID: activity.authorId,
            currentUserID: currentUserID,
            isGoing: activity.isGoing
        )
    }

    func load(activity: Activity, currentUserID: UUID?) async {
        updateAccess(activity: activity, currentUserID: currentUserID)
        guard !isLoading else { return }
        guard let repository else { errorMessage = ActivityPhotoError.requestFailed.localizedDescription; return }
        isLoading = true
        defer { isLoading = false }
        do {
            photos = try await repository.fetchPhotos(activityID: activity.id)
            errorMessage = nil
        } catch {
            errorMessage = photoErrorMessage(error)
        }
    }

    func upload(_ item: PhotosPickerItem?, activity: Activity) async {
        guard let item, let repository, canUpload, !isUploading else { return }
        guard ActivityPhotoRules.canAddPhoto(currentCount: photos.count) else {
            errorMessage = ActivityPhotoError.limitReached.localizedDescription
            return
        }
        isUploading = true
        errorMessage = nil
        defer { isUploading = false }
        do {
            guard let source = try await item.loadTransferable(type: Data.self) else {
                throw ActivityPhotoError.invalidImage
            }
            let jpeg = try await Task.detached(priority: .userInitiated) { try ActivityPhotoProcessor.process(data: source) }.value
            try Task.checkCancellation()
            _ = try await repository.uploadPhoto(activityID: activity.id, jpegData: jpeg)
            await load(activity: activity, currentUserID: currentUserID)
        } catch {
            errorMessage = photoErrorMessage(error)
        }
    }

    func canDelete(_ photo: ActivityPhoto) -> Bool {
        guard let activityAuthorID else { return false }
        return ActivityPhotoRules.canDelete(
            uploaderID: photo.uploaderId,
            activityAuthorID: activityAuthorID,
            currentUserID: currentUserID
        )
    }

    func delete(_ photo: ActivityPhoto) async {
        guard let repository, canDelete(photo), deletingPhotoID == nil else { return }
        deletingPhotoID = photo.id
        errorMessage = nil
        defer { deletingPhotoID = nil }
        do {
            try await repository.deletePhoto(photoID: photo.id)
            photos.removeAll { $0.id == photo.id }
        } catch {
            errorMessage = photoErrorMessage(error)
        }
    }
}

private func photoErrorMessage(_ error: Error) -> String {
    (error as? ActivityPhotoError)?.errorDescription ?? ActivityPhotoError.requestFailed.localizedDescription
}
