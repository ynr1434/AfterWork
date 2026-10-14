import XCTest
import Supabase
@testable import AfterWork

private final class ActivityURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}

private struct EmptyAuthStorage: AuthLocalStorage {
    func store(key: String, value: Data) throws { }
    func retrieve(key: String) throws -> Data? { nil }
    func remove(key: String) throws { }
}

@MainActor
final class ActivityRepositoryTests: XCTestCase {
    private func repository() -> ActivityRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ActivityURLProtocol.self]
        let client = SupabaseClient(supabaseURL: URL(string: "https://activity-tests.invalid")!,
                                    supabaseKey: "sb_publishable_test_fixture_only",
                                    options: .init(auth: .init(storage: EmptyAuthStorage(), autoRefreshToken: false,
                                                              emitLocalSessionAsInitialSession: true),
                                                   global: .init(session: URLSession(configuration: configuration))))
        return ActivityRepository(client: client, currentUserID: { ActivityFixtures.authorID })
    }

    nonisolated private func query(_ request: URLRequest) -> [String: String] {
        Dictionary((URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, new in new })
    }

    nonisolated private func body(_ request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let size = stream.read(&buffer, maxLength: buffer.count)
                if size <= 0 { break }
                data.append(contentsOf: buffer.prefix(size))
            }
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testUpcomingQueryUsesCategorySortingAndGoingCountEmbed() async throws {
        let fixture = try JSONSerialization.data(withJSONObject: [ActivityFixtures.json(count: 3)])
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        ActivityURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            let query = self.query(request)
            XCTAssertEqual(query["category_id"], "eq.\(ActivityFixtures.categoryID.uuidString)")
            XCTAssertEqual(query["going.status"], "eq.going")
            XCTAssertEqual(query["start_at"], "gte.\(date.ISO8601Format())")
            XCTAssertTrue(query["order"]?.contains("start_at.asc") == true)
            XCTAssertTrue(query["select"]?.contains("activity_participants_activity_id_fkey(count)") == true)
            return (200, fixture)
        }
        let rows = try await repository().fetchUpcomingActivities(from: date, categoryId: ActivityFixtures.categoryID)
        XCTAssertEqual(rows.first?.participantCount, 3)
    }

    func testCreationDerivesAuthorAndPreservesText() async throws {
        let fixture = try JSONSerialization.data(withJSONObject: [ActivityFixtures.json()])
        ActivityURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(self.query(request)["on_conflict"])
            let body = try self.body(request)
            XCTAssertEqual(body["author_id"] as? String, ActivityFixtures.authorID.uuidString)
            XCTAssertEqual(body["title"] as? String, "  Keep spaces  ")
            XCTAssertNotNil(body["id"] as? String)
            XCTAssertTrue(body["end_at"] is NSNull)
            XCTAssertTrue(body["location_address"] is NSNull)
            return (201, fixture)
        }
        var draft = ActivityDraft()
        draft.title = "  Keep spaces  "; draft.locationName = "Office"
        draft.categoryId = ActivityFixtures.categoryID
        let created = try await repository().createActivity(draft)
        XCTAssertEqual(created.authorId, ActivityFixtures.authorID)
    }

    func testCreateRetriesOnceWithSameIDAfterTransportLoss() async throws {
        let fixture = try JSONSerialization.data(withJSONObject: [ActivityFixtures.json()])
        var attempts = 0
        var ids: [String] = []
        ActivityURLProtocol.handler = { request in
            attempts += 1
            ids.append((try self.body(request))["id"] as? String ?? "")
            if attempts == 1 { throw URLError(.networkConnectionLost) }
            return (201, fixture)
        }
        var draft = ActivityDraft()
        draft.title = "Retry me"
        draft.categoryId = ActivityFixtures.categoryID
        draft.locationName = "Office"
        let created = try await repository().createActivity(draft, id: ActivityFixtures.activityID)
        XCTAssertEqual(created.id, ActivityFixtures.activityID)
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(ids, [ActivityFixtures.activityID.uuidString, ActivityFixtures.activityID.uuidString])
    }

    func testDuplicateAfterRetryFetchesOwnedActivity() async throws {
        let fixture = try JSONSerialization.data(withJSONObject: [ActivityFixtures.json()])
        var attempts = 0
        ActivityURLProtocol.handler = { request in
            attempts += 1
            if attempts == 1 {
                let error = try JSONSerialization.data(withJSONObject: [
                    "code": "23505", "message": "duplicate key value violates unique constraint"
                ])
                return (409, error)
            }
            XCTAssertEqual(request.httpMethod, "GET")
            return (200, fixture)
        }
        var draft = ActivityDraft(); draft.title = "Already created"; draft.categoryId = ActivityFixtures.categoryID; draft.locationName = "Office"
        let activity = try await repository().createActivity(draft, id: ActivityFixtures.activityID)
        XCTAssertEqual(activity.id, ActivityFixtures.activityID)
        XCTAssertEqual(attempts, 2)
    }

    func testDuplicateRecoveryRejectsDifferentOwner() async throws {
        let other = UUID(uuidString: "61000000-0000-0000-0000-000000000001")!
        var json = ActivityFixtures.json(); json["author_id"] = other.uuidString
        let fixture = try JSONSerialization.data(withJSONObject: [json])
        var attempts = 0
        ActivityURLProtocol.handler = { request in
            attempts += 1
            if attempts == 1 {
                let error = try JSONSerialization.data(withJSONObject: ["code": "23505", "message": "duplicate"])
                return (409, error)
            }
            return (200, fixture)
        }
        var draft = ActivityDraft(); draft.title = "Owned elsewhere"; draft.categoryId = ActivityFixtures.categoryID; draft.locationName = "Office"
        do {
            _ = try await repository().createActivity(draft, id: ActivityFixtures.activityID)
            XCTFail("Expected ownership rejection")
        } catch let error as ActivityError {
            XCTAssertEqual(error.localizedDescription, ActivityError.notOwner.localizedDescription)
        }
    }

    func testUpdateCannotSendAuthorAndClearsNullableFields() async throws {
        let fixture = try JSONSerialization.data(withJSONObject: [ActivityFixtures.json()])
        ActivityURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            let query = self.query(request)
            XCTAssertEqual(query["id"], "eq.\(ActivityFixtures.activityID.uuidString)")
            XCTAssertEqual(query["author_id"], "eq.\(ActivityFixtures.authorID.uuidString)")
            let body = try self.body(request)
            XCTAssertNil(body["author_id"])
            XCTAssertNil(body["id"])
            XCTAssertTrue(body["end_at"] is NSNull)
            XCTAssertTrue(body["max_participants"] is NSNull)
            XCTAssertTrue(body["location_address"] is NSNull)
            return (200, fixture)
        }
        let draft = ActivityDraft(activity: try ActivityFixtures.record().activity())
        _ = try await repository().updateActivity(id: ActivityFixtures.activityID, draft: draft)
    }

    func testZeroRowDeleteIsNotReportedAsSuccess() async throws {
        ActivityURLProtocol.handler = { request in
            let table = request.url!.pathComponents.last!
            switch (request.httpMethod, table) {
            case ("GET", "activities"):
                XCTAssertEqual(self.query(request)["author_id"], "eq.\(ActivityFixtures.authorID.uuidString)")
                let json = try JSONSerialization.data(withJSONObject: [["id": ActivityFixtures.activityID.uuidString]])
                return (200, json)
            case ("GET", "activity_photos"):
                return (200, Data("[]".utf8))
            case ("DELETE", "activities"):
                XCTAssertEqual(self.query(request)["author_id"], "eq.\(ActivityFixtures.authorID.uuidString)")
                return (200, Data("[]".utf8))
            default:
                XCTFail("Unexpected activity-delete request: \(request.httpMethod ?? "nil") \(table)")
                return (500, Data())
            }
        }
        do {
            try await repository().deleteActivity(id: ActivityFixtures.activityID)
            XCTFail("Empty deletion must fail")
        } catch ActivityError.notOwner { }
    }

    func testMissingDetailAndEmptyFeedStayEmpty() async throws {
        ActivityURLProtocol.handler = { _ in (200, Data("[]".utf8)) }
        let repository = repository()
        let detail = try await repository.fetchActivity(id: ActivityFixtures.activityID)
        let upcoming = try await repository.fetchUpcomingActivities()
        XCTAssertNil(detail)
        XCTAssertTrue(upcoming.isEmpty)
    }

    func testValidationDoesNotIssueNetworkRequest() async {
        ActivityURLProtocol.handler = { _ in XCTFail("Invalid form must not issue a request"); return (200, Data("[]".utf8)) }
        do {
            _ = try await repository().createActivity(ActivityDraft())
            XCTFail("Invalid form must fail")
        } catch ActivityError.invalid { }
        catch { XCTFail("Unexpected error") }
    }
}
