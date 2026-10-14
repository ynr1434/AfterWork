import XCTest
@testable import AfterWork

@MainActor
final class Stage15Tests: XCTestCase {
    func testFeedHasTwelveUniqueAlmatyPlaceIdeas() {
        let suggestions = AlmatyPlaceSuggestions.all
        XCTAssertEqual(suggestions.count, 12)
        XCTAssertEqual(Set(suggestions.map(\.id)).count, suggestions.count)
        XCTAssertTrue(suggestions.allSatisfy { !$0.name.isEmpty && !$0.pitch.isEmpty && !$0.details.isEmpty && !$0.groupIdea.isEmpty && !$0.imageName.isEmpty })
        XCTAssertEqual(Set(suggestions.map(\.imageName)).count, suggestions.count)
    }

    func testCreateActivityCanBePrefilledWithSavedPlace() async {
        let model = ActivityFormViewModel(
            initialLocationName: "Line Brew",
            initialLocationAddress: "City centre"
        )
        XCTAssertEqual(model.draft.locationName, "Line Brew")
        XCTAssertEqual(model.draft.locationAddress, "City centre")
    }

    func testSelectedCoverUploadsAfterActivityExists() async throws {
        let createdActivity = try ActivityFixtures.record().activity()
        var uploadedActivityID: UUID?
        var uploadedData: Data?
        let model = ActivityFormViewModel(
            categoriesLoader: { [ActivityFixtures.category()] },
            saveActivity: { _, id in
                XCTAssertNil(id)
                return createdActivity
            },
            uploadCoverImage: { activityID, data in
                uploadedActivityID = activityID
                uploadedData = data
                var result = createdActivity
                result.coverImageURL = "https://example.invalid/signed-cover"
                return result
            }
        )
        model.draft.title = "After work plan"
        model.draft.categoryId = ActivityFixtures.categoryID
        model.draft.locationName = "Office"
        model.setSelectedCoverImage(Data([0xFF, 0xD8, 0xFF]))
        await model.loadCategories()

        let saved = await model.save(userID: createdActivity.authorId)

        XCTAssertEqual(saved?.coverImageURL, "https://example.invalid/signed-cover")
        XCTAssertEqual(uploadedActivityID, createdActivity.id)
        XCTAssertEqual(uploadedData, Data([0xFF, 0xD8, 0xFF]))
        XCTAssertNil(model.coverUploadErrorMessage)
    }

    func testCoverUploadFailureKeepsPublishedActivityOnCategoryArtwork() async throws {
        let createdActivity = try ActivityFixtures.record().activity()
        let model = ActivityFormViewModel(
            categoriesLoader: { [ActivityFixtures.category()] },
            saveActivity: { _, _ in createdActivity },
            uploadCoverImage: { _, _ in throw ActivityPhotoError.requestFailed }
        )
        model.draft.title = "After work plan"
        model.draft.categoryId = ActivityFixtures.categoryID
        model.draft.locationName = "Office"
        model.setSelectedCoverImage(Data([0xFF, 0xD8, 0xFF]))
        await model.loadCategories()

        let saved = await model.save(userID: createdActivity.authorId)

        XCTAssertEqual(saved?.id, createdActivity.id)
        XCTAssertNil(saved?.coverImageURL)
        XCTAssertNotNil(model.coverUploadErrorMessage)
    }

    func testScheduleUsesLocalCalendarAtMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 5 * 3600))
        let parser = ISO8601DateFormatter()
        let now = try XCTUnwrap(parser.date(from: "2026-10-14T18:30:00Z"))
        let event = try XCTUnwrap(parser.date(from: "2026-10-14T20:15:00Z"))
        let text = ActivityDateText.schedule(event, now: now, calendar: calendar, locale: Locale(identifier: "en_GB"))
        XCTAssertTrue(text.hasPrefix("Tomorrow ·"))
        XCTAssertTrue(text.contains("01:15"))
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        XCTAssertTrue(ActivityDateText.schedule(event, now: now, calendar: calendar, locale: Locale(identifier: "en_GB")).hasPrefix("Today ·"))
    }

    func testScheduleRespectsLocaleHourCycle() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-14T18:15:00Z"))
        let uk = ActivityDateText.schedule(date, now: date, calendar: calendar, locale: Locale(identifier: "en_GB"))
        let us = ActivityDateText.schedule(date, now: date, calendar: calendar, locale: Locale(identifier: "en_US"))
        XCTAssertTrue(uk.contains("18:15"))
        XCTAssertTrue(us.contains("6:15"))
        XCTAssertTrue(us.contains("PM"))
    }

    func testFormSubmitRemainsDisabledDuringSaveAndFailurePreservesDraft() async throws {
        let activity = try ActivityFixtures.record().activity()
        var pending: CheckedContinuation<Activity, Error>?
        let model = ActivityFormViewModel(activity: activity, categoriesLoader: { [ActivityFixtures.category()] }, saveActivity: { _, _ in
            try await withCheckedThrowingContinuation { pending = $0 }
        })
        XCTAssertFalse(model.canSubmit)
        await model.loadCategories()
        XCTAssertTrue(model.canSubmit)
        let task = Task { await model.save(userID: activity.authorId) }
        while pending == nil { await Task.yield() }
        XCTAssertFalse(model.canSubmit)
        let duplicate = await model.save(userID: activity.authorId)
        XCTAssertNil(duplicate)
        pending?.resume(throwing: URLError(.notConnectedToInternet))
        _ = await task.value
        XCTAssertTrue(model.canSubmit)
        XCTAssertEqual(model.draft.title, activity.title)
        XCTAssertNotNil(model.errorMessage)
    }

    func testCategoryLoadingPreventsPublishAndDuplicateLoads() async throws {
        let activity = try ActivityFixtures.record().activity()
        var pending: CheckedContinuation<[CategoryDTO], Error>?
        var calls = 0
        let model = ActivityFormViewModel(activity: activity, categoriesLoader: {
            calls += 1
            return try await withCheckedThrowingContinuation { pending = $0 }
        })
        let task = Task { await model.loadCategories() }
        while pending == nil { await Task.yield() }
        XCTAssertFalse(model.canSubmit)
        await model.loadCategories()
        XCTAssertEqual(calls, 1)
        pending?.resume(returning: [ActivityFixtures.category()])
        await task.value
        XCTAssertTrue(model.canSubmit)
    }

    func testCommentValidationDisablesBlankAndOversizedDrafts() async {
        let model = CommentsViewModel()
        for text in ["", " \n\t ", String(repeating: "a", count: 5001)] {
            model.draft = text
            XCTAssertFalse(model.canSubmit)
            await model.submit(activityID: UUID())
            XCTAssertEqual(model.errorMessage, CommentError.invalidBody.localizedDescription)
            XCTAssertEqual(model.draft, text)
            XCTAssertFalse(model.isSending)
        }
        model.draft = String(repeating: "a", count: 5000)
        XCTAssertTrue(model.canSubmit)
    }

    func testCommentErrorsNeverExposeRawBackendDetails() {
        let error = NSError(domain: "private", code: 401, userInfo: [NSLocalizedDescriptionKey: "secret token and database detail"])
        XCTAssertFalse(commentErrorMessage(error).contains("secret"))
        XCTAssertEqual(commentErrorMessage(CommentError.notOwner), CommentError.notOwner.localizedDescription)
    }

    func testMentionAfterNewlineReplacesOnlyCurrentToken() {
        let profile = ProfileDTO(id: UUID(), email: nil, displayName: "Alex Lee", avatarUrl: nil,
                                 department: nil, jobTitle: nil, interests: nil, createdAt: .now, updatedAt: .now)
        let suggestion = MentionSuggestion(profile: profile)
        XCTAssertEqual(MentionComposer.insert(suggestion, into: "Hello\n@Al"), "Hello\n@Alex Lee ")
        XCTAssertEqual(MentionComposer.insert(suggestion, into: "Hello\t@Al"), "Hello\t@Alex Lee ")
        XCTAssertNil(MentionComposer.query(in: "Hello @Al "))
        XCTAssertEqual(MentionComposer.insert(suggestion, into: "Hello"), "Hello")
    }

    func testPhotoAccessUpdatesImmediatelyAfterJoinAndLeave() async throws {
        var activity = try ActivityFixtures.record().activity()
        let member = UUID()
        let model = ActivityPhotosViewModel()
        activity.isGoing = false
        model.updateAccess(activity: activity, currentUserID: member)
        XCTAssertFalse(model.canUpload)
        activity.isGoing = true
        model.updateAccess(activity: activity, currentUserID: member)
        XCTAssertTrue(model.canUpload)
        activity.isGoing = false
        model.updateAccess(activity: activity, currentUserID: member)
        XCTAssertFalse(model.canUpload)
        model.updateAccess(activity: activity, currentUserID: nil)
        XCTAssertFalse(model.canUpload)
    }
    func testSharedEngagementSurvivesListRefreshWithFreshParticipantCount() async throws {
        var activity = try ActivityFixtures.record().activity()
        let model = ActivityListViewModel(loadCategories: { [ActivityFixtures.category()] },
                                          loadActivities: { _, _, _, _ in [activity] })
        await model.load()
        model.applyEngagement([activity.id: ActivityEngagementState(
            isSaved: true, isSkipped: true, isGoing: true, participantCount: 2, participantInitials: ["AL"]
        )])
        XCTAssertEqual(model.activities.first?.participantInitials, ["AL"])
        activity.participantCount = 5
        await model.load(refresh: true)
        let refreshed = try XCTUnwrap(model.activities.first)
        XCTAssertTrue(refreshed.isSaved)
        XCTAssertTrue(refreshed.isSkipped)
        XCTAssertTrue(refreshed.isGoing)
        XCTAssertEqual(refreshed.participantCount, 5)
    }

    func testDetailsUnsaveAndLeaveReplaceSharedState() async throws {
        let activity = try ActivityFixtures.record().activity()
        let model = ActivityListViewModel(loadCategories: { [] }, loadActivities: { _, _, _, _ in [activity] })
        await model.load()
        model.applyEngagement([activity.id: ActivityEngagementState(isSaved: true, isGoing: true, participantCount: 2)])
        model.applyEngagement([activity.id: ActivityEngagementState(isSaved: false, isGoing: false, participantCount: 1)])
        let updated = try XCTUnwrap(model.activities.first)
        XCTAssertFalse(updated.isSaved)
        XCTAssertFalse(updated.isGoing)
        XCTAssertEqual(updated.participantCount, 1)
        await model.load(refresh: true)
        XCTAssertFalse(try XCTUnwrap(model.activities.first).isSaved)
        XCTAssertFalse(try XCTUnwrap(model.activities.first).isGoing)
    }

    func testSharedEngagementIsIsolatedBetweenListInstances() async throws {
        let activity = try ActivityFixtures.record().activity()
        let first = ActivityListViewModel(loadCategories: { [] }, loadActivities: { _, _, _, _ in [activity] })
        await first.load()
        first.applyEngagement([activity.id: ActivityEngagementState(isSaved: true, isSkipped: true)])
        let nextUser = ActivityListViewModel(loadCategories: { [] }, loadActivities: { _, _, _, _ in [activity] })
        await nextUser.load()
        XCTAssertFalse(try XCTUnwrap(nextUser.activities.first).isSaved)
        XCTAssertFalse(try XCTUnwrap(nextUser.activities.first).isSkipped)
    }

}
