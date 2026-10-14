import Supabase
import XCTest

@testable import AfterWork

private final class PushNotificationURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var handler:
    (@Sendable (URLRequest) throws -> (Int, Data, [String: String]))?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    do {
      guard let handler = Self.handler else { throw URLError(.badServerResponse) }
      let (status, data, headers) = try handler(request)
      client?.urlProtocol(
        self,
        didReceive: HTTPURLResponse(
          url: request.url!, statusCode: status, httpVersion: nil,
          headerFields: headers.merging(["Content-Type": "application/json"]) { a, _ in a })!,
        cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch { client?.urlProtocol(self, didFailWithError: error) }
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
