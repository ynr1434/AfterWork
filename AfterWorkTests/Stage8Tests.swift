import XCTest
@testable import AfterWork

final class Stage8Tests: XCTestCase {
    func testMentionQueryAndInsertion() {
        let profile = ProfileDTO(id: UUID(), email: nil, displayName: "Alisher Khan", avatarUrl: nil,
                                 department: nil, jobTitle: nil, interests: nil, createdAt: .now, updatedAt: .now)
        let suggestion = MentionSuggestion(profile: profile)
        XCTAssertEqual(MentionComposer.query(in: "Hi @Ali"), "Ali")
        XCTAssertEqual(MentionComposer.insert(suggestion, into: "Hi @Ali"), "Hi @Alisher Khan ")
    }

    func testMentionIDsDeduplicate() {
        let id = UUID()
        XCTAssertEqual(MentionComposer.uniqueUserIDs([id, id]).count, 1)
    }

    func testMentionSearchPatternUsesTrimmedQueryPrefix() {
        XCTAssertEqual(MentionSearchPattern.prefix(for: "  Ali  "), "Ali%")
        XCTAssertNotEqual(MentionSearchPattern.prefix(for: "Ali"), "(trimmed)%")
        XCTAssertNil(MentionSearchPattern.prefix(for: "  \n "))
    }

    func testNotificationKindMappingAndUnreadCount() {
        XCTAssertEqual(NotificationKind(rawValue: "mention"), .mention)
        XCTAssertEqual(NotificationKind(rawValue: "activityComment"), .activityComment)
        XCTAssertEqual(NotificationKind(rawValue: "futureType"), .unknown)
    }

    func testCommentDTOMapsAuthorAndEditedState() {
        let now = Date()
        let dto = CommentDTO(id: UUID(), activityId: UUID(), authorId: UUID(), body: "Hello",
                             createdAt: now, updatedAt: now.addingTimeInterval(2),
                             author: CommentAuthorDTO(id: UUID(), displayName: "Dima", avatarUrl: nil))
        let comment = Comment(dto: dto)
        XCTAssertEqual(comment.authorName, "Dima")
        XCTAssertTrue(comment.isEdited)
    }

    func testCommentUpdatePayloadContainsOnlyMutableBody() throws {
        let data = try JSONEncoder().encode(CommentUpdatePayload(body: "Edited"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(object, ["body": "Edited"])
    }

    func testCommentDeleteSucceedsOnFirstRequestForOnlySelectedID() async throws {
        let id = UUID()
        var deleteIDs: [UUID] = []
        var existenceChecks = 0
        try await CommentDeleteRetry.delete(commentID: id, delete: { requestedID in
            deleteIDs.append(requestedID)
            return true
        }, exists: { _ in
            existenceChecks += 1
            return true
        })
        XCTAssertEqual(deleteIDs, [id])
        XCTAssertEqual(existenceChecks, 0)
    }

    func testCommentDeleteRetriesNetworkConnectionLostOnce() async throws {
        let id = UUID()
        var attempts = 0
        try await CommentDeleteRetry.delete(commentID: id, delete: { requestedID in
            XCTAssertEqual(requestedID, id)
            attempts += 1
            if attempts == 1 { throw URLError(.networkConnectionLost) }
            return true
        }, exists: { _ in XCTFail("Existence check is unnecessary after successful retry"); return false })
        XCTAssertEqual(attempts, 2)
    }

    func testCommentDeleteTreatsAlreadyAbsentAfterRetryAsSuccess() async throws {
        let id = UUID()
        var attempts = 0
        var checkedID: UUID?
        try await CommentDeleteRetry.delete(commentID: id, delete: { requestedID in
            XCTAssertEqual(requestedID, id)
            attempts += 1
            if attempts == 1 { throw URLError(.networkConnectionLost) }
            return false
        }, exists: { requestedID in
            checkedID = requestedID
            return false
        })
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(checkedID, id)
    }

    func testCommentDeleteFailsWhenRetryFailsAndCommentStillExists() async {
        let id = UUID()
        var attempts = 0
        do {
            try await CommentDeleteRetry.delete(commentID: id, delete: { _ in
                attempts += 1
                throw URLError(.networkConnectionLost)
            }, exists: { _ in true })
            XCTFail("Expected deletion to fail while the comment still exists")
        } catch let error as CommentError {
            XCTAssertEqual(error, .notOwner)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(attempts, 2)
    }

    func testCommentDeleteDoesNotRetryNonTransientError() async {
        let id = UUID()
        var attempts = 0
        do {
            try await CommentDeleteRetry.delete(commentID: id, delete: { _ in
                attempts += 1
                throw URLError(.badServerResponse)
            }, exists: { _ in XCTFail("Do not check existence for a non-transient server error"); return false })
            XCTFail("Expected deletion to fail")
        } catch let error as CommentError {
            XCTAssertEqual(error, .requestFailed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(attempts, 1)
    }

    func testCommentDeleteDoesNotRetryAuthOrRLSFailures() async {
        for failure in [NSError(domain: "Supabase.AuthError", code: 401), NSError(domain: "PostgrestError", code: 42501)] {
            var attempts = 0
            do {
                try await CommentDeleteRetry.delete(commentID: UUID(), delete: { _ in
                    attempts += 1
                    throw failure
                }, exists: { _ in XCTFail("Do not check existence after an authorization error"); return false })
                XCTFail("Expected deletion to fail")
            } catch let error as CommentError {
                XCTAssertEqual(error, .requestFailed)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(attempts, 1)
        }
    }
}
