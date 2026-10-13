import Foundation
import Observation

@MainActor @Observable
final class ActivityEngagementViewModel {
    private(set) var states: [UUID: ActivityEngagementState] = [:]
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    private(set) var needsAuthentication = false
    @ObservationIgnored private let repository: ActivityEngagementRepository?

    init(repository: ActivityEngagementRepository? = nil) {
        self.repository = repository ?? (try? ActivityEngagementRepository(client: SupabaseManager.shared.client))
    }

    func load(activityIDs: [UUID]) async {
        guard !activityIDs.isEmpty else { return }
        guard let repository else { return }
        do {
            states.merge(try await repository.fetchEngagements(activityIds: activityIDs)) { _, new in new }
            errorMessage = nil
        } catch {
            errorMessage = activityErrorMessage(error)
            needsAuthentication = isActivitySessionError(error)
        }
    }

    func state(for activity: Activity) -> Activity {
        guard let state = states[activity.id] else { return activity }
        var result = activity
        result.isSaved = state.isSaved
        result.isSkipped = state.isSkipped
        result.isGoing = state.isGoing
        if let count = state.participantCount { result.participantCount = count }
        if let initials = state.participantInitials { result.participantInitials = initials }
        return result
    }

    func save(activityId: UUID, isSaved: Bool) async {
        guard let repository else { return }
        await mutate(activityId: activityId) { try await repository.setSaved(activityId: activityId, isSaved: isSaved) }
    }

    func skip(activityId: UUID, isSkipped: Bool = true) async {
        guard let repository else { return }
        await mutate(activityId: activityId) { try await repository.setSkipped(activityId: activityId, isSkipped: isSkipped) }
    }

    func join(activityId: UUID) async {
        guard let repository else { return }
        await mutate(activityId: activityId) { try await repository.joinActivity(activityId: activityId) }
    }

    func leave(activityId: UUID) async {
        guard let repository else { return }
        await mutate(activityId: activityId) { try await repository.leaveActivity(activityId: activityId) }
    }

    func participants(activityId: UUID) async -> [ParticipantDTO] {
        guard let repository else { return [] }
        do { return try await repository.fetchParticipants(activityId: activityId) }
        catch {
            errorMessage = activityErrorMessage(error)
            needsAuthentication = isActivitySessionError(error)
            return []
        }
    }

    private func mutate(activityId: UUID, operation: () async throws -> ActivityEngagementState) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do { states[activityId] = try await operation() }
        catch {
            errorMessage = activityErrorMessage(error)
            needsAuthentication = isActivitySessionError(error)
        }
    }
}
