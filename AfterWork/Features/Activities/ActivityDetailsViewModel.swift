import Foundation
import Observation

@MainActor @Observable
final class ActivityDetailsViewModel {
    let id: UUID
    private(set) var activity: Activity?
    private(set) var isLoading = false
    private(set) var isDeleting = false
    private(set) var errorMessage: String?
    private(set) var needsAuthentication = false
    @ObservationIgnored private let fetch: (UUID) async throws -> Activity?
    @ObservationIgnored private let delete: (UUID) async throws -> Void
    @ObservationIgnored private var generation = UUID()

    init(id: UUID,
         fetch: @escaping (UUID) async throws -> Activity? = { id in
             try await ActivityRepository(client: SupabaseManager.shared.client).fetchActivity(id: id)
         },
         delete: @escaping (UUID) async throws -> Void = { id in
             try await ActivityRepository(client: SupabaseManager.shared.client).deleteActivity(id: id)
         }) {
        self.id = id
        self.fetch = fetch
        self.delete = delete
    }

    func load() async {
        guard !isLoading, !isDeleting else { return }
        let token = UUID()
        generation = token
        isLoading = true
        errorMessage = nil
        defer { if generation == token { isLoading = false } }
        do {
            let result = try await fetch(id)
            guard !Task.isCancelled, generation == token else { return }
            activity = result
            if result == nil { errorMessage = ActivityError.notFound.localizedDescription }
        } catch is CancellationError { }
        catch {
            guard generation == token else { return }
            errorMessage = activityErrorMessage(error)
            needsAuthentication = isActivitySessionError(error)
        }
    }

    func didSave(_ activity: Activity) {
        generation = UUID()
        isLoading = false
        self.activity = activity
        errorMessage = nil
    }

    func remove(userID: UUID?) async -> Bool {
        guard !isDeleting, let activity else { return false }
        guard userID == activity.authorId else {
            errorMessage = ActivityError.notOwner.localizedDescription
            return false
        }
        generation = UUID()
        isLoading = false
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }
        do {
            try await delete(id)
            self.activity = nil
            return true
        } catch {
            errorMessage = activityErrorMessage(error)
            needsAuthentication = isActivitySessionError(error)
            return false
        }
    }
}
