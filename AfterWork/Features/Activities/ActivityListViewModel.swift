import Foundation
import Observation

/// One bounded list shared by Feed and Explore; no separate activity cache or auth client.
@MainActor @Observable
final class ActivityListViewModel {
    private(set) var activities: [Activity] = []
    private(set) var categories: [CategoryDTO] = []
    var selectedCategoryId: UUID?
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    private(set) var needsAuthentication = false
    private(set) var hasMore = false
    private(set) var revision = 0
    private var engagementStates: [UUID: ActivityEngagementState] = [:]
    private var offset = 0
    private var fromDate = Date.now
    private let pageSize = 50
    @ObservationIgnored private var request: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var requestCategory: UUID?
    @ObservationIgnored private let loadCategories: () async throws -> [CategoryDTO]
    @ObservationIgnored private let loadActivities: (Date, UUID?, Int, Int) async throws -> [Activity]

    init(
        loadCategories: @escaping () async throws -> [CategoryDTO] = {
            try await ActivityRepository(client: SupabaseManager.shared.client).fetchCategories()
        },
        loadActivities: @escaping (Date, UUID?, Int, Int) async throws -> [Activity] = { date, category, offset, limit in
            try await ActivityRepository(client: SupabaseManager.shared.client)
                .fetchUpcomingActivities(from: date, categoryId: category, offset: offset, limit: limit)
        }
    ) {
        self.loadCategories = loadCategories
        self.loadActivities = loadActivities
    }

    var visibleActivities: [Activity] {
        ActivityDayGroup.upcoming(activities).filter { selectedCategoryId == nil || $0.categoryId == selectedCategoryId }
    }

    func applyEngagement(_ states: [UUID: ActivityEngagementState]) {
        engagementStates.merge(states) { _, new in new }
        activities = activities.map { activity in
            guard let state = states[activity.id] else { return activity }
            var result = activity
            result.isSaved = state.isSaved
            result.isSkipped = state.isSkipped
            result.isGoing = state.isGoing
            if let participantCount = state.participantCount { result.participantCount = participantCount }
            if let initials = state.participantInitials { result.participantInitials = initials }
            return result
        }
    }

    func load(refresh: Bool = false, more: Bool = false) async {
        let category = selectedCategoryId
        if isLoading, requestCategory == category, let request {
            await request.value
            return
        }
        if hasLoaded, !refresh, !more, requestCategory == category { return }
        if more && !hasMore { return }
        request?.cancel()
        let token = UUID()
        generation = token
        let categoryChanged = requestCategory != category
        requestCategory = category
        if categoryChanged { activities = []; hasLoaded = false; hasMore = false }
        isLoading = true
        errorMessage = nil
        needsAuthentication = false
        let append = more && !categoryChanged
        if !append { fromDate = .now; offset = 0 }
        let date = fromDate
        let pageOffset = offset
        request = Task { [weak self, loadCategories, loadActivities] in
            do {
                async let catalog = loadCategories()
                async let rows = loadActivities(date, category, pageOffset, 50)
                let (categories, page) = try await (catalog, rows)
                guard let self, !Task.isCancelled, self.generation == token else { return }
                self.categories = categories
                let all = append ? self.activities + page : page
                var seen = Set<UUID>()
                self.activities = ActivityDayGroup.upcoming(all).filter { seen.insert($0.id).inserted }.map { activity in
                    // The list endpoint returns counts but not the current user's actions.
                    // Preserve confirmed action flags while accepting fresh backend counts.
                    guard let state = self.engagementStates[activity.id] else { return activity }
                    var result = activity
                    result.isSaved = state.isSaved
                    result.isSkipped = state.isSkipped
                    result.isGoing = state.isGoing
                    return result
                }
                self.offset = pageOffset + page.count
                self.hasMore = page.count == self.pageSize
                self.hasLoaded = true
            } catch {
                guard let self, !Task.isCancelled, self.generation == token else { return }
                self.errorMessage = activityErrorMessage(error)
                self.needsAuthentication = isActivitySessionError(error)
            }
            guard let self, self.generation == token else { return }
            self.isLoading = false
            self.request = nil
        }
        await request?.value
    }

    func didSave(_ activity: Activity) {
        invalidateRequest()
        activities.removeAll { $0.id == activity.id }
        if activity.startsAt >= .now, selectedCategoryId == nil || selectedCategoryId == activity.categoryId {
            activities.append(activity)
            activities = ActivityDayGroup.upcoming(activities)
        }
        revision += 1
    }

    func didDelete(id: UUID) {
        invalidateRequest()
        activities.removeAll { $0.id == id }
        engagementStates.removeValue(forKey: id)
        revision += 1
    }

    private func invalidateRequest() {
        generation = UUID()
        request?.cancel()
        request = nil
        isLoading = false
    }
}

func activityErrorMessage(_ error: Error) -> String {
    if let error = error as? ActivityError { return error.localizedDescription }
    if let error = error as? DatabaseError { return error.localizedDescription }
    return ActivityError.requestFailed.localizedDescription
}

func isActivitySessionError(_ error: Error) -> Bool {
    if case ActivityError.signInRequired = error { return true }
    return false
}
