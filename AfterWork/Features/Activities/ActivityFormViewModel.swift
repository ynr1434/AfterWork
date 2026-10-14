import Foundation
import Observation

@MainActor @Observable
final class ActivityFormViewModel {
    var draft: ActivityDraft
    private(set) var categories: [CategoryDTO] = []
    private(set) var isLoadingCategories = false
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var needsAuthentication = false
    private(set) var selectedCoverImageData: Data?
    private(set) var isProcessingCoverImage = false
    private(set) var coverSelectionErrorMessage: String?
    private(set) var coverUploadErrorMessage: String?
    private let editingActivity: Activity?
    @ObservationIgnored private let categoriesLoader: () async throws -> [CategoryDTO]
    @ObservationIgnored private let saveActivity: (ActivityDraft, UUID?) async throws -> Activity
    @ObservationIgnored private let uploadCoverImage: (UUID, Data) async throws -> Activity

    init(activity: Activity? = nil,
         initialLocationName: String? = nil,
         initialLocationAddress: String? = nil,
         categoriesLoader: @escaping () async throws -> [CategoryDTO] = {
             try await ActivityRepository(client: SupabaseManager.shared.client).fetchCategories()
         },
         saveActivity: @escaping (ActivityDraft, UUID?) async throws -> Activity = { draft, id in
             let repository = try ActivityRepository(client: SupabaseManager.shared.client)
             if let id { return try await repository.updateActivity(id: id, draft: draft) }
             return try await repository.createActivity(draft)
         },
         uploadCoverImage: @escaping (UUID, Data) async throws -> Activity = { activityID, data in
             let repository = try ActivityRepository(client: SupabaseManager.shared.client)
             return try await repository.attachCoverImage(activityID: activityID, jpegData: data)
         }) {
        var initialDraft = ActivityDraft(activity: activity)
        if activity == nil {
            initialDraft.locationName = initialLocationName ?? initialDraft.locationName
            initialDraft.locationAddress = initialLocationAddress ?? initialDraft.locationAddress
        }
        editingActivity = activity
        draft = initialDraft
        self.categoriesLoader = categoriesLoader
        self.saveActivity = saveActivity
        self.uploadCoverImage = uploadCoverImage
    }

    var existingCoverImageURL: String? { editingActivity?.coverImageURL }

    func setSelectedCoverImage(_ data: Data?) {
        selectedCoverImageData = data
        coverSelectionErrorMessage = nil
        coverUploadErrorMessage = nil
    }

    func setCoverImageProcessing(_ isProcessing: Bool) {
        isProcessingCoverImage = isProcessing
    }

    func setCoverImageSelectionError(_ message: String) {
        coverSelectionErrorMessage = message
    }

    var canSubmit: Bool { !isSaving && !isLoadingCategories && validationMessage == nil }

    var isEditing: Bool { editingActivity != nil }
    var validationMessage: String? {
        if let message = draft.validationMessage { return message }
        if !categories.contains(where: { $0.id == draft.categoryId }) { return "Choose an available category." }
        return nil
    }

    func loadCategories() async {
        guard !isLoadingCategories else { return }
        isLoadingCategories = true
        defer { isLoadingCategories = false }
        do {
            categories = try await categoriesLoader()
            guard !categories.isEmpty else { throw ActivityError.categoriesUnavailable }
            errorMessage = nil
        } catch is CancellationError { }
        catch { errorMessage = activityErrorMessage(error); needsAuthentication = isActivitySessionError(error) }
    }

    func save(userID: UUID?) async -> Activity? {
        guard !isSaving else { return nil }
        errorMessage = nil
        coverUploadErrorMessage = nil
        guard let userID else {
            errorMessage = ActivityError.signInRequired.localizedDescription
            needsAuthentication = true
            return nil
        }
        if let original = editingActivity, original.authorId != userID {
            errorMessage = ActivityError.notOwner.localizedDescription
            return nil
        }
        if let message = validationMessage { errorMessage = message; return nil }
        isSaving = true
        defer { isSaving = false }
        do {
            let activity = try await saveActivity(draft, editingActivity?.id)
            guard let selectedCoverImageData else { return activity }
            do {
                return try await uploadCoverImage(activity.id, selectedCoverImageData)
            } catch is CancellationError {
                coverUploadErrorMessage = "The activity was saved, but the selected cover photo upload was interrupted. The previous cover or category artwork will remain."
                return activity
            } catch {
                coverUploadErrorMessage = "The activity was saved, but its selected cover photo couldn't be uploaded. The previous cover or category artwork will remain."
                return activity
            }
        }
        catch is CancellationError { return nil }
        catch {
            errorMessage = activityErrorMessage(error)
            needsAuthentication = isActivitySessionError(error)
            return nil
        }
    }

    func resetAfterCreation() {
        if !isEditing {
            draft = ActivityDraft()
            setSelectedCoverImage(nil)
        }
    }
}
