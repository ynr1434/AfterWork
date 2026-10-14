import XCTest
@testable import AfterWork

@MainActor
final class Stage15Tests: XCTestCase {
    func testSkippingKeepsSuccessorAtSamePosition() {
        XCTAssertEqual(EngagementRules.nextIndex(after: .skip, index: 0, remainingCount: 3, advanceSaved: false), 0)
        XCTAssertEqual(EngagementRules.nextIndex(after: .skip, index: 2, remainingCount: 2, advanceSaved: false), 1)
        XCTAssertEqual(EngagementRules.nextIndex(after: .skip, index: 0, remainingCount: 0, advanceSaved: false), 0)
    }

    func testSaveSwipeAdvancesButSaveButtonAndJoinKeepPosition() {
        XCTAssertEqual(EngagementRules.nextIndex(after: .save, index: 0, remainingCount: 3, advanceSaved: true), 1)
        for action in [FeedView.Action.save, .unsave, .join, .leave] {
            XCTAssertEqual(EngagementRules.nextIndex(after: action, index: 0, remainingCount: 3, advanceSaved: false), 0)
        }
        XCTAssertEqual(EngagementRules.nextIndex(after: .save, index: 2, remainingCount: 3, advanceSaved: true), 2)
    }

    func testFeedPositionIsReadableAndClamped() {
        XCTAssertEqual(EngagementRules.positionText(index: 1, count: 4), "2 of 4")
        XCTAssertEqual(EngagementRules.positionText(index: 9, count: 4), "4 of 4")
        XCTAssertEqual(EngagementRules.positionText(index: -2, count: 4), "1 of 4")
        XCTAssertEqual(EngagementRules.positionText(index: 0, count: 0), "No activities")
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

    func testPhotoAccessUpdatesImmediatelyAfterJoinAndLeave() throws {
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
}
