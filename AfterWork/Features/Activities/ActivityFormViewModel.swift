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
    private let editingActivity: Activity?
    @ObservationIgnored private let categoriesLoader: () async throws -> [CategoryDTO]
    @ObservationIgnored private let saveActivity: (ActivityDraft, UUID?) async throws -> Activity

    init(activity: Activity? = nil,
         categoriesLoader: @escaping () async throws -> [CategoryDTO] = {
             try await ActivityRepository(client: SupabaseManager.shared.client).fetchCategories()
         },
         saveActivity: @escaping (ActivityDraft, UUID?) async throws -> Activity = { draft, id in
             let repository = try ActivityRepository(client: SupabaseManager.shared.client)
             if let id { return try await repository.updateActivity(id: id, draft: draft) }
             return try await repository.createActivity(draft)
         }) {
        editingActivity = activity
        draft = ActivityDraft(activity: activity)
        self.categoriesLoader = categoriesLoader
        self.saveActivity = saveActivity
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
        do { return try await saveActivity(draft, editingActivity?.id) }
        catch is CancellationError { return nil }
        catch {
            errorMessage = activityErrorMessage(error)
            needsAuthentication = isActivitySessionError(error)
            return nil
        }
    }

    func resetAfterCreation() { if !isEditing { draft = ActivityDraft() } }
}
