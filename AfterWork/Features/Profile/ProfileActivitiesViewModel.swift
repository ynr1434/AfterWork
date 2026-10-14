import Foundation
import Observation

@MainActor @Observable
final class ProfileActivitiesViewModel {
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var saved: [Activity] = []
    private(set) var joined: [Activity] = []
    private(set) var created: [Activity] = []
    private(set) var errorMessage: String?
    private let engagement: ActivityEngagementRepository?
    private let activities: ActivityRepository?

    init() {
        if let client = try? SupabaseManager.shared.client {
            engagement = ActivityEngagementRepository(client: client)
            activities = ActivityRepository(client: client)
        } else {
            engagement = nil
            activities = nil
        }
    }

    func load() async {
        guard !isLoading else { return }
        guard let engagement, let activities else { errorMessage = ActivityError.requestFailed.localizedDescription; return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let savedIDs = engagement.fetchSavedActivityIDs()
            async let joinedIDs = engagement.fetchJoinedActivityIDs()
            async let createdRows = activities.fetchActivitiesCreatedByCurrentUser()
            let (savedIDsResult, joinedIDsResult, createdResult) = try await (savedIDs, joinedIDs, createdRows)
            async let savedRows = activities.fetchActivities(ids: savedIDsResult)
            async let joinedRows = activities.fetchActivities(ids: joinedIDsResult)
            let (savedResult, joinedResult) = try await (savedRows, joinedRows)
            guard !Task.isCancelled else { return }
            saved = savedResult
            joined = joinedResult.filter { $0.startsAt >= .now }
            created = createdResult
            hasLoaded = true
            errorMessage = nil
        } catch {
            errorMessage = activityErrorMessage(error)
        }
    }
}
