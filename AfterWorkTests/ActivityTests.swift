import XCTest
@testable import AfterWork

@MainActor
final class ActivityTests: XCTestCase {
    func validDraft() -> ActivityDraft {
        var draft = ActivityDraft()
        draft.title = "Volleyball after work"
        draft.categoryId = UUID()
        draft.locationName = "Office Sports Hall"
        return draft
    }

    func testRequiredAndOptionalValidation() {
        var draft = validDraft()
        XCTAssertNil(draft.validationMessage)
        draft.title = " \n "
        XCTAssertNotNil(draft.validationMessage)
        draft = validDraft(); draft.categoryId = nil
        XCTAssertNotNil(draft.validationMessage)
        draft = validDraft(); draft.locationName = "\n "
        XCTAssertNotNil(draft.validationMessage)
        for capacity in ["0", "-1", "1.5", "abc", " 12 ", "2147483648"] {
            draft = validDraft(); draft.maximumParticipants = capacity
            XCTAssertNotNil(draft.validationMessage, capacity)
        }
        for capacity in ["", "1", "12"] {
            draft = validDraft(); draft.maximumParticipants = capacity
            XCTAssertNil(draft.validationMessage)
        }
    }

    func testLengthLimitsAndNoSilentTrimming() {
        var draft = validDraft()
        draft.title = String(repeating: "a", count: 160)
        draft.locationName = String(repeating: "a", count: 200)
        draft.description = String(repeating: "a", count: 10_000)
        XCTAssertNil(draft.validationMessage)
        draft.title += "a"; XCTAssertNotNil(draft.validationMessage)
        draft = validDraft(); draft.locationName = String(repeating: "a", count: 201)
        XCTAssertNotNil(draft.validationMessage)
        draft = validDraft(); draft.description = String(repeating: "a", count: 10_001)
        XCTAssertNotNil(draft.validationMessage)
        draft = validDraft(); draft.title = "  Keep spacing  "
        XCTAssertNil(draft.validationMessage)
        XCTAssertEqual(draft.title, "  Keep spacing  ")
    }

    func testEndDateCrossingMidnightAndInvalidTimes() {
        var draft = validDraft()
        draft.hasEnd = true
        draft.endsAt = draft.startsAt
        XCTAssertNotNil(draft.validationMessage)
        draft.endsAt = draft.startsAt.addingTimeInterval(-1)
        XCTAssertNotNil(draft.validationMessage)
        draft.endsAt = draft.startsAt.addingTimeInterval(86_400)
        XCTAssertNil(draft.validationMessage)
        draft.startsAt = Date(timeIntervalSince1970: .infinity)
        XCTAssertNotNil(draft.validationMessage)
    }

    func testCategorySlugMappingIncludingUnknownCategory() {
        for category in ActivityCategory.allCases {
            XCTAssertEqual(ActivityCategory(databaseSlug: category.databaseSlug), category)
        }
        XCTAssertEqual(ActivityCategory.boardGames.databaseSlug, "board_games")
        XCTAssertEqual(ActivityCategory(databaseSlug: "future-category"), .other)
    }

    func testLocalDayGroupsAtDSTAndWeekBoundaries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.firstWeekday = 2
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 23))!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        XCTAssertEqual(ActivityDayGroup.group(for: now, now: now, calendar: calendar), .today)
        XCTAssertEqual(ActivityDayGroup.group(for: tomorrow, now: now, calendar: calendar), .tomorrow)
        XCTAssertEqual(ActivityDayGroup.group(for: calendar.date(byAdding: .day, value: 3, to: now)!, now: now, calendar: calendar), .later)
        let monday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 10))!
        let thursday = calendar.date(byAdding: .day, value: 3, to: monday)!
        XCTAssertEqual(ActivityDayGroup.group(for: thursday, now: monday, calendar: calendar), .thisWeek)
        // Tomorrow must win even when it belongs to the next week.
        let sunday = calendar.date(byAdding: .day, value: 6, to: monday)!
        XCTAssertEqual(ActivityDayGroup.group(for: calendar.date(byAdding: .day, value: 1, to: sunday)!, now: sunday, calendar: calendar), .tomorrow)
    }

    func testUpcomingSortingAndEditRoundTrip() {
        let now = Date.now
        var a = MockActivities.preview
        // Activity fields are immutable; create a fixture by mapping JSON below instead.
        a.endsAt = a.startsAt.addingTimeInterval(3600)
        a.locationAddress = "Somewhere"
        let draft = ActivityDraft(activity: a)
        XCTAssertEqual(draft.categoryId, a.categoryId)
        XCTAssertEqual(draft.endsAt, a.endsAt)
        XCTAssertEqual(draft.maximumParticipants, "12")
        let input = MockActivities.makeActivities(relativeTo: now).reversed()
        let sorted = ActivityDayGroup.upcoming(Array(input), now: now)
        XCTAssertTrue(sorted.allSatisfy { $0.startsAt >= now })
        XCTAssertEqual(sorted.map(\.startsAt), sorted.map(\.startsAt).sorted())
    }

    func testRelationalDTOMappingNoInventedAttendees() throws {
        let record = try ActivityFixtures.record(count: 2)
        let activity = record.activity()
        XCTAssertEqual(activity.id, ActivityFixtures.activityID)
        XCTAssertEqual(activity.authorId, ActivityFixtures.authorID)
        XCTAssertEqual(activity.categoryId, ActivityFixtures.categoryID)
        XCTAssertEqual(activity.category, .boardGames)
        XCTAssertEqual(activity.categoryDisplayName, "Board Games")
        XCTAssertEqual(activity.organizerName, "Ada Lovelace")
        XCTAssertEqual(activity.organizerInitials, "AL")
        XCTAssertEqual(activity.participantCount, 2)
        XCTAssertTrue(activity.participantInitials.isEmpty)
        XCTAssertNil(activity.maxParticipants)
        XCTAssertNil(activity.endsAt)
        let missing = try ActivityFixtures.record(count: 0, organizer: NSNull())
        XCTAssertEqual(missing.activity().participantCount, 0)
        XCTAssertEqual(missing.activity().organizerName, "Organizer unavailable")
    }

    func testSwipeThresholdRequiresMeaningfulMovement() {
        XCTAssertNil(EngagementRules.swipeAction(for: 119))
        XCTAssertEqual(EngagementRules.swipeAction(for: 120), .save)
        XCTAssertEqual(EngagementRules.swipeAction(for: -120), .skip)
    }

    func testFeedFilteringExcludesSkippedAndPastActivities() {
        let now = Date.now
        var skipped = MockActivities.preview
        skipped.isSkipped = true
        var past = MockActivities.preview
        past = Activity(id: past.id, authorId: past.authorId, categoryId: past.categoryId,
                        title: past.title, description: past.description, category: past.category,
                        startsAt: now.addingTimeInterval(-60), locationName: past.locationName,
                        participantCount: past.participantCount, maxParticipants: past.maxParticipants,
                        organizerName: past.organizerName, organizerInitials: past.organizerInitials,
                        participantInitials: past.participantInitials)
        XCTAssertTrue(EngagementRules.feedActivities([skipped, past], now: now).isEmpty)
    }
}

@MainActor
enum ActivityFixtures {
    nonisolated static let activityID = UUID(uuidString: "50000000-0000-0000-0000-000000000001")!
    nonisolated static let authorID = UUID(uuidString: "60000000-0000-0000-0000-000000000001")!
    nonisolated static let categoryID = UUID(uuidString: "70000000-0000-0000-0000-000000000001")!
    static func json(count: Int = 0, organizer: Any? = nil) -> [String: Any] {
        ["id": activityID.uuidString, "author_id": authorID.uuidString, "category_id": categoryID.uuidString,
         "title": "Board Games", "description": "", "start_at": Date.now.addingTimeInterval(86_400).ISO8601Format(),
         "location_name": "Office", "created_at": "2026-10-13T00:00:00Z", "updated_at": "2026-10-13T00:00:00Z",
         "category": ["id": categoryID.uuidString, "slug": "board_games", "name": "Board Games", "sf_symbol": "dice.fill", "created_at": "2026-10-13T00:00:00Z"],
         "organizer": organizer ?? ["id": authorID.uuidString, "display_name": "Ada Lovelace"],
         "going": [["count": count]]]
    }
    static func record(count: Int = 0, organizer: Any? = nil) throws -> ActivityRecordDTO {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ActivityRecordDTO.self, from: JSONSerialization.data(withJSONObject: json(count: count, organizer: organizer)))
    }
    static func category() -> CategoryDTO {
        CategoryDTO(id: categoryID, slug: "board_games", name: "Board Games", sfSymbol: "dice.fill", createdAt: .now)
    }
}
