import XCTest
@testable import AfterWork

final class Stage9Tests: XCTestCase {
    func testPhotoResizeKeepsAspectRatioAndNeverUpscales() {
        XCTAssertEqual(ActivityPhotoProcessor.resizedSize(width: 4400, height: 2200),
                       ActivityPhotoPixelSize(width: 2200, height: 1100))
        XCTAssertEqual(ActivityPhotoProcessor.resizedSize(width: 1000, height: 500),
                       ActivityPhotoPixelSize(width: 1000, height: 500))
        XCTAssertNil(ActivityPhotoProcessor.resizedSize(width: 0, height: 1))
    }

    func testProcessedPhotoDataMustBeNonemptyAndWithinStorageLimit() {
        XCTAssertNoThrow(try ActivityPhotoProcessor.validateProcessedData(Data([0xFF, 0xD8])))
        XCTAssertThrowsError(try ActivityPhotoProcessor.validateProcessedData(Data())) {
            XCTAssertEqual($0 as? ActivityPhotoError, .invalidImage)
        }
        XCTAssertThrowsError(try ActivityPhotoProcessor.validateProcessedData(
            Data(repeating: 0, count: ActivityPhotoRules.maximumUploadBytes + 1)
        )) { XCTAssertEqual($0 as? ActivityPhotoError, .tooLarge) }
    }

    func testPhotoCountLimitAndUploadEligibility() {
        let user = UUID()
        let organizer = UUID()
        XCTAssertTrue(ActivityPhotoRules.canAddPhoto(currentCount: 9))
        XCTAssertFalse(ActivityPhotoRules.canAddPhoto(currentCount: 10))
        XCTAssertTrue(ActivityPhotoRules.canUpload(activityAuthorID: organizer, currentUserID: organizer, isGoing: false))
        XCTAssertTrue(ActivityPhotoRules.canUpload(activityAuthorID: organizer, currentUserID: user, isGoing: true))
        XCTAssertFalse(ActivityPhotoRules.canUpload(activityAuthorID: organizer, currentUserID: user, isGoing: false))
        XCTAssertFalse(ActivityPhotoRules.canUpload(activityAuthorID: organizer, currentUserID: nil, isGoing: true))
    }

    func testPhotoStoragePathUsesActivityUploaderAndUniquePhotoIDs() {
        let activity = UUID()
        let uploader = UUID()
        let first = ActivityPhotoRules.storagePath(activityID: activity, uploaderID: uploader, photoID: UUID())
        let second = ActivityPhotoRules.storagePath(activityID: activity, uploaderID: uploader, photoID: UUID())
        XCTAssertTrue(first.hasPrefix("activities/\(activity.uuidString.lowercased())/\(uploader.uuidString.lowercased())/"))
        XCTAssertTrue(first.hasSuffix(".jpg"))
        XCTAssertNotEqual(first, second)
    }

    func testOnlyUploaderOrOrganizerCanDeletePhoto() {
        let author = UUID()
        let uploader = UUID()
        let other = UUID()
        XCTAssertTrue(ActivityPhotoRules.canDelete(uploaderID: uploader, activityAuthorID: author, currentUserID: uploader))
        XCTAssertTrue(ActivityPhotoRules.canDelete(uploaderID: uploader, activityAuthorID: author, currentUserID: author))
        XCTAssertFalse(ActivityPhotoRules.canDelete(uploaderID: uploader, activityAuthorID: author, currentUserID: other))
        XCTAssertFalse(ActivityPhotoRules.canDelete(uploaderID: uploader, activityAuthorID: author, currentUserID: nil))
    }

    func testPhotoDTOMapsStorageMetadata() {
        let id = UUID()
        let activityID = UUID()
        let userID = UUID()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let dto = ActivityPhotoDTO(id: id, activityId: activityID, uploaderId: userID,
                                  storagePath: "activities/a/u/p.jpg", createdAt: date)
        let photo = ActivityPhoto(dto: dto)
        XCTAssertEqual(photo.id, id)
        XCTAssertEqual(photo.activityId, activityID)
        XCTAssertEqual(photo.uploaderId, userID)
        XCTAssertEqual(photo.storagePath, "activities/a/u/p.jpg")
        XCTAssertEqual(photo.createdAt, date)
    }
}
