import Foundation
import Observation

@MainActor @Observable
final class ProfileActivitiesViewModel {
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
        guard let engagement, let activities else { return }
        do {
            async let savedIDs = engagement.fetchSavedActivityIDs()
            async let joinedIDs = engagement.fetchJoinedActivityIDs()
            async let createdRows = activities.fetchActivitiesCreatedByCurrentUser()
            let (savedIDsResult, joinedIDsResult, createdResult) = try await (savedIDs, joinedIDs, createdRows)
            async let savedRows = activities.fetchActivities(ids: savedIDsResult)
            async let joinedRows = activities.fetchActivities(ids: joinedIDsResult)
            saved = try await savedRows
            let joinedResult = try await joinedRows
            joined = joinedResult.filter { $0.startsAt >= .now }
            created = createdResult
            errorMessage = nil
        } catch {
            errorMessage = activityErrorMessage(error)
        }
    }
}
