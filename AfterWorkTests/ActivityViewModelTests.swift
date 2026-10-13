import XCTest
@testable import AfterWork

@MainActor
final class ActivityViewModelTests: XCTestCase {
    func testEmptyAndNetworkErrorNeverBecomeMocks() async {
        var fail = false
        let model = ActivityListViewModel(loadCategories: { [ActivityFixtures.category()] }, loadActivities: { _, _, _, _ in
            if fail { throw URLError(.notConnectedToInternet) }
            return []
        })
        await model.load()
        XCTAssertTrue(model.hasLoaded)
        XCTAssertTrue(model.activities.isEmpty)
        XCTAssertNil(model.errorMessage)
        fail = true
        await model.load(refresh: true)
        XCTAssertTrue(model.activities.isEmpty)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
        fail = false
        await model.load(refresh: true)
        XCTAssertNil(model.errorMessage)
    }

    func testCategorySwitchDiscardsLateResponse() async throws {
        let activity = try ActivityFixtures.record().activity()
        var pending: CheckedContinuation<[Activity], Error>?
        let secondCategory = UUID()
        let model = ActivityListViewModel(loadCategories: { [ActivityFixtures.category()] }, loadActivities: { _, category, _, _ in
            if category == nil { return try await withCheckedThrowingContinuation { pending = $0 } }
            XCTAssertEqual(category, secondCategory)
            return []
        })
        let original = Task { await model.load() }
        while pending == nil { await Task.yield() }
        model.selectedCategoryId = secondCategory
        await model.load()
        pending?.resume(returning: [activity])
        await original.value
        XCTAssertTrue(model.activities.isEmpty)
        XCTAssertTrue(model.hasLoaded)
    }

    func testSuccessfulMutationsUpdateSharedLists() async throws {
        let activity = try ActivityFixtures.record().activity()
        let model = ActivityListViewModel(loadCategories: { [ActivityFixtures.category()] }, loadActivities: { _, _, _, _ in [] })
        await model.load()
        model.didSave(activity)
        XCTAssertEqual(model.visibleActivities.map(\.id), [activity.id])
        model.didSave(activity)
        XCTAssertEqual(model.visibleActivities.count, 1)
        model.didDelete(id: activity.id)
        XCTAssertTrue(model.visibleActivities.isEmpty)
        XCTAssertEqual(model.revision, 3)
    }

    func testSaveFailurePreservesFormAndOwnerCheck() async throws {
        let activity = try ActivityFixtures.record().activity()
        var calls = 0
        let model = ActivityFormViewModel(activity: activity, categoriesLoader: { [ActivityFixtures.category()] }, saveActivity: { _, _ in
            calls += 1
            throw ActivityError.requestFailed
        })
        await model.loadCategories()
        model.draft.title = "Unsaved edits"
        let forbidden = await model.save(userID: UUID())
        XCTAssertNil(forbidden)
        XCTAssertEqual(calls, 0)
        let failure = await model.save(userID: activity.authorId)
        XCTAssertNil(failure)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(model.draft.title, "Unsaved edits")
        XCTAssertFalse(model.isSaving)
        XCTAssertNotNil(model.errorMessage)
    }

    func testDuplicateSaveAndUnauthenticatedSaveAreBlocked() async throws {
        let activity = try ActivityFixtures.record().activity()
        var calls = 0
        var pending: CheckedContinuation<Activity, Error>?
        let model = ActivityFormViewModel(activity: activity, categoriesLoader: { [ActivityFixtures.category()] }, saveActivity: { _, _ in
            calls += 1
            return try await withCheckedThrowingContinuation { pending = $0 }
        })
        await model.loadCategories()
        let absent = await model.save(userID: nil)
        XCTAssertNil(absent)
        XCTAssertTrue(model.needsAuthentication)
        let original = Task { await model.save(userID: activity.authorId) }
        while pending == nil { await Task.yield() }
        let duplicate = await model.save(userID: activity.authorId)
        XCTAssertNil(duplicate)
        XCTAssertEqual(calls, 1)
        pending?.resume(returning: activity)
        let saved = await original.value
        XCTAssertEqual(saved?.id, activity.id)
    }

    func testDeleteRequiresOwnerAndServerSuccess() async throws {
        let activity = try ActivityFixtures.record().activity()
        var calls = 0
        var fail = true
        let model = ActivityDetailsViewModel(id: activity.id, fetch: { _ in activity }, delete: { _ in
            calls += 1
            if fail { throw ActivityError.requestFailed }
        })
        await model.load()
        let forbidden = await model.remove(userID: UUID())
        XCTAssertFalse(forbidden)
        XCTAssertEqual(calls, 0)
        let failed = await model.remove(userID: activity.authorId)
        XCTAssertFalse(failed)
        XCTAssertNotNil(model.activity)
        fail = false
        let deleted = await model.remove(userID: activity.authorId)
        XCTAssertTrue(deleted)
        XCTAssertNil(model.activity)
    }
}
