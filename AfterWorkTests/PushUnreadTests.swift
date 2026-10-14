import Supabase
import XCTest

@testable import AfterWork

private final class PushNotificationURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var handler:
    (@Sendable (URLRequest) throws -> (Int, Data, [String: String]))?
  nonisolated(unsafe) static var delay: (@Sendable (URLRequest) -> DispatchSemaphore?)?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    do {
      guard let handler = Self.handler else { throw URLError(.badServerResponse) }
      let (status, data, headers) = try handler(request)
      if let gate = Self.delay?(request) {
        DispatchQueue.global().async { [self] in
          _ = gate.wait(timeout: .now() + 5)
          finish(status: status, data: data, headers: headers)
        }
      } else { finish(status: status, data: data, headers: headers) }
    } catch { client?.urlProtocol(self, didFailWithError: error) }
  }
  private func finish(status: Int, data: Data, headers: [String: String]) {
      client?.urlProtocol(
        self,
        didReceive: HTTPURLResponse(
          url: request.url!, statusCode: status, httpVersion: nil,
          headerFields: headers.merging(["Content-Type": "application/json"]) { a, _ in a })!,
        cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
private struct PushUnreadStorage: AuthLocalStorage {
  func store(key: String, value: Data) throws {}
  func retrieve(key: String) throws -> Data? { nil }
  func remove(key: String) throws {}
}
@MainActor
final class PushUnreadTests: XCTestCase {
  private func repository(user: UUID) -> NotificationRepository {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PushNotificationURLProtocol.self]
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://push-unread-tests.invalid")!,
      supabaseKey: "sb_publishable_test_fixture_only",
      options: .init(
        auth: .init(
          storage: PushUnreadStorage(), autoRefreshToken: false,
          emitLocalSessionAsInitialSession: true),
        global: .init(session: URLSession(configuration: configuration))))
    return NotificationRepository(client: client, currentUserID: { user })
  }
  func testBadgeUsesExactBackendCountBeyondVisibleHundredRows() async {
    let user = UUID()
    PushNotificationURLProtocol.handler = { request in
      let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
      XCTAssertTrue(query.contains { $0.name == "user_id" && $0.value == "eq.\(user.uuidString)" })
      if request.httpMethod == "HEAD" {
        XCTAssertTrue(query.contains { $0.name == "is_read" && $0.value == "eq.false" })
        return (200, Data(), ["Content-Range": "*/137"])
      }
      return (200, Data("[]".utf8), [:])
    }
    let model = NotificationsViewModel(repository: repository(user: user))
    await model.load()
    XCTAssertEqual(model.notifications.count, 0)
    XCTAssertEqual(model.unreadCount, 137)
    XCTAssertNil(model.errorMessage)
  }
  func testZeroRowReadUpdateIsRejectedInsteadOfFakingReadState() async {
    PushNotificationURLProtocol.handler = { request in
      XCTAssertEqual(request.httpMethod, "PATCH")
      return (200, Data("[]".utf8), [:])
    }
    do {
      try await repository(user: UUID()).markAsRead(notificationID: UUID())
      XCTFail("Missing server confirmation must fail")
    } catch {}
  }
  func testConfirmedReadUsesRecipientFilterAndReturnedID() async throws {
    let user = UUID()
    let id = UUID()
    let response = try JSONSerialization.data(withJSONObject: [
      ["id": id.uuidString, "is_read": true]
    ])
    PushNotificationURLProtocol.handler = { request in
      let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
      XCTAssertTrue(query.contains { $0.name == "user_id" && $0.value == "eq.\(user.uuidString)" })
      XCTAssertTrue(query.contains { $0.name == "id" && $0.value == "eq.\(id.uuidString)" })
      XCTAssertTrue(
        request.value(forHTTPHeaderField: "Prefer")?.contains("return=representation") == true)
      return (200, response, [:])
    }
    try await repository(user: user).markAsRead(notificationID: id)
  }
}

private final class NotificationRaceState: @unchecked Sendable {
    let lock = NSLock()
    private var getCount = 0
    private var patchCount = 0
    private var read = false
    func response(method: String) -> (gets: Int, patches: Int, isRead: Bool) {
        lock.withLock {
            if method == "GET" { getCount += 1 }
            if method == "PATCH" { patchCount += 1; read = true }
            return (getCount, patchCount, read)
        }
    }
}

extension PushUnreadTests {
    func testRepeatedMarkAllIsBlockedWhileRequestIsPending() async {
        let gate = DispatchSemaphore(value: 0)
        let started = expectation(description: "Read update started")
        let state = NotificationRaceState()
        PushNotificationURLProtocol.handler = { request in
            let snapshot = state.response(method: request.httpMethod ?? "")
            if request.httpMethod == "HEAD" { return (200, Data(), ["Content-Range": snapshot.isRead ? "*/0" : "*/1"]) }
            return (200, Data("[]".utf8), [:])
        }
        PushNotificationURLProtocol.delay = { request in
            guard request.httpMethod == "PATCH" else { return nil }
            started.fulfill()
            return gate
        }
        defer { PushNotificationURLProtocol.delay = nil }
        let model = NotificationsViewModel(repository: repository(user: UUID()))
        await model.load()
        let task = Task { await model.markAllRead() }
        await fulfillment(of: [started], timeout: 3)
        XCTAssertTrue(model.isMarkingAll)
        await model.markAllRead()
        XCTAssertEqual(state.response(method: "").patches, 1)
        gate.signal()
        await task.value
        XCTAssertFalse(model.isMarkingAll)
        XCTAssertEqual(model.unreadCount, 0)
    }

    func testLateRefreshCannotUndoConfirmedRead() async throws {
        let user = UUID(), id = UUID()
        let gate = DispatchSemaphore(value: 0)
        let started = expectation(description: "Stale refresh pending")
        let state = NotificationRaceState()
        PushNotificationURLProtocol.handler = { request in
            let snapshot = state.response(method: request.httpMethod ?? "")
            if request.httpMethod == "HEAD" { return (200, Data(), ["Content-Range": snapshot.isRead ? "*/0" : "*/1"]) }
            if request.httpMethod == "PATCH" {
                return (200, try JSONSerialization.data(withJSONObject: [["id": id.uuidString, "is_read": true]]), [:])
            }
            let row: [String: Any] = ["id": id.uuidString, "user_id": user.uuidString, "type": "mention", "title": "Mention", "body": "Open the activity", "is_read": snapshot.isRead, "created_at": "2026-10-14T00:00:00Z"]
            return (200, try JSONSerialization.data(withJSONObject: [row]), [:])
        }
        PushNotificationURLProtocol.delay = { request in
            guard request.httpMethod == "GET", state.response(method: "").gets == 2 else { return nil }
            started.fulfill()
            return gate
        }
        defer { PushNotificationURLProtocol.delay = nil }
        let model = NotificationsViewModel(repository: repository(user: user))
        await model.load()
        let notification = try XCTUnwrap(model.notifications.first)
        let refresh = Task { await model.load() }
        await fulfillment(of: [started], timeout: 3)
        await model.markRead(notification)
        XCTAssertTrue(model.notifications[0].isRead)
        gate.signal()
        await refresh.value
        XCTAssertTrue(model.notifications[0].isRead)
        XCTAssertEqual(model.unreadCount, 0)
        XCTAssertEqual(state.response(method: "").gets, 3)
    }
}
