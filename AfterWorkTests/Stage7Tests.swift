import XCTest
@testable import AfterWork

@MainActor
final class Stage7Tests: XCTestCase {
    func testReminderOffsetsAndTitles() {
        XCTAssertEqual(ActivityReminderOption.none.offset, 0)
        XCTAssertEqual(ActivityReminderOption.tenMinutes.offset, 600)
        XCTAssertEqual(ActivityReminderOption.thirtyMinutes.offset, 1_800)
        XCTAssertEqual(ActivityReminderOption.oneHour.offset, 3_600)
        XCTAssertEqual(ActivityReminderOption.oneHour.title, "1 hour before")
    }

    func testLocalCalendarAndReminderMappingsPersist() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "stage7-tests-\(UUID().uuidString)"))
        let preferences = ActivityLocalPreferences(defaults: defaults)
        let activityID = UUID()
        XCTAssertNil(preferences.eventIdentifier(for: activityID))
        XCTAssertEqual(preferences.reminder(for: activityID), .none)
        preferences.setEventIdentifier("event-identifier", for: activityID)
        preferences.setReminder(.thirtyMinutes, for: activityID)
        XCTAssertEqual(preferences.eventIdentifier(for: activityID), "event-identifier")
        XCTAssertEqual(preferences.reminder(for: activityID), .thirtyMinutes)
        preferences.removeAll(for: activityID)
        XCTAssertNil(preferences.eventIdentifier(for: activityID))
        XCTAssertEqual(preferences.reminder(for: activityID), .none)
    }

    func testStableReminderIdentifier() {
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        XCTAssertEqual(LocalNotificationManager.identifier(for: id), "afterwork.activity.AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE.reminder")
    }
}
