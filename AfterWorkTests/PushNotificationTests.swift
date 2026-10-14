import UserNotifications
import XCTest

@testable import AfterWork

@MainActor
final class PushNotificationTests: XCTestCase {
  private let user = UUID()
  private let installation = PushInstallation(id: UUID(), secret: String(repeating: "a", count: 64))
  private func preferences() -> UserDefaults {
    let name = "afterwork.push.tests.\(UUID())"
    let defaults = UserDefaults(suiteName: name)!
    addTeardownBlock { defaults.removePersistentDomain(forName: name) }
    return defaults
  }
  private func destination() -> PushDestination {
    PushDestination(userInfo: [
      "notification_id": UUID().uuidString, "activity_id": UUID().uuidString, "type": "mention",
    ])!
  }
  private func notification(_ destination: PushDestination, user: UUID, isRead: Bool = false)
    -> AppNotification
  {
    AppNotification(
      dto: NotificationDTO(
        id: destination.id, userId: user, type: destination.type, title: "Mention",
        body: "Open activity",
        activityId: destination.activityID, actorUserId: UUID(), isRead: isRead, createdAt: .now))
  }

  func testTokenNormalizationAndEnvironmentAreIndependentOfBuildConfiguration() {
    XCTAssertEqual(PushToken.normalize(Data([0, 15, 16, 255])), "000f10ff")
    XCTAssertNil(PushToken.normalize(Data()))
    XCTAssertNil(PushToken.normalize(Data(repeating: 0, count: 257)))
    XCTAssertEqual(APNsEnvironment(entitlement: "development"), .sandbox)
    XCTAssertEqual(APNsEnvironment(entitlement: "production"), .production)
    XCTAssertNil(APNsEnvironment(entitlement: nil))
    XCTAssertNil(APNsEnvironment(entitlement: "Debug"))
  }
  func testPayloadRejectsMalformedOrUnrelatedNotifications() {
    XCTAssertNil(PushDestination(userInfo: [:]))
    XCTAssertNil(
      PushDestination(userInfo: [
        "notification_id": "invalid", "activity_id": UUID().uuidString, "type": "mention",
      ]))
    XCTAssertNil(
      PushDestination(userInfo: [
        "notification_id": UUID().uuidString, "activity_id": UUID().uuidString, "type": "broadcast",
      ]))
    XCTAssertEqual(destination().type, "mention")
    XCTAssertEqual(PushNotificationManager.mapPermission(.provisional), .allowed)
    XCTAssertEqual(PushNotificationManager.mapPermission(.ephemeral), .allowed)
    XCTAssertEqual(PushNotificationManager.mapPermission(.denied), .denied)
  }
  func testNoPermissionPromptOrRegistrationAtLoginWithoutOptIn() async {
    var requests = 0
    var registrations = 0
    let manager = PushNotificationManager(
      preferences: preferences(), permissionStatus: { .notDetermined },
      requestPermission: {
        requests += 1
        return true
      }, installation: { self.installation }, environment: { .sandbox },
      save: { _, _, _ in XCTFail("No save without opt in") }, remove: { _ in },
      registerWithAPNs: { registrations += 1 }, unregisterFromAPNs: {})
    await manager.synchronize(userID: user)
    XCTAssertEqual(requests, 0)
    XCTAssertEqual(registrations, 0)
    XCTAssertFalse(manager.enabled)
  }
  func testOptInRegistersCurrentAndRotatedTokensAndLogoutRemovesOnlyInstallation() async throws {
    var status: PushPermission = .notDetermined
    var prompts = 0
    var tokens: [String] = []
    var removed: [UUID] = []
    let manager = PushNotificationManager(
      preferences: preferences(), permissionStatus: { status },
      requestPermission: {
        prompts += 1
        status = .allowed
        return true
      },
      installation: { self.installation }, environment: { .production },
      save: { _, token, environment in
        XCTAssertEqual(environment, .production)
        tokens.append(token)
      }, remove: { removed.append($0.id) }, registerWithAPNs: {}, unregisterFromAPNs: {})
    await manager.synchronize(userID: user)
    await manager.enable()
    await manager.receivedDeviceToken(Data([1, 2]))
    await manager.receivedDeviceToken(Data([3, 4]))
    XCTAssertEqual(tokens, ["0102", "0304"])
    XCTAssertTrue(manager.registered)
    XCTAssertEqual(prompts, 1)
    try await manager.prepareForSignOut()
    XCTAssertEqual(removed, [installation.id])
    XCTAssertNil(manager.activeUserID)
    XCTAssertFalse(manager.registered)
  }
  func testCleanupFailurePreservesUserForRetryAndClearsNoUnrelatedState() async {
    let defaults = preferences()
    defaults.set(true, forKey: "push.optedIn.\(user.uuidString)")
    var fail = true
    let manager = PushNotificationManager(
      preferences: defaults, permissionStatus: { .allowed }, installation: { self.installation },
      environment: { .sandbox },
      save: { _, _, _ in }, remove: { _ in if fail { throw URLError(.notConnectedToInternet) } },
      registerWithAPNs: {}, unregisterFromAPNs: {})
    await manager.synchronize(userID: user)
    await manager.receivedDeviceToken(Data([1]))
    do {
      try await manager.prepareForSignOut()
      XCTFail("Must not report successful cleanup")
    } catch {}
    XCTAssertEqual(manager.activeUserID, user)
    fail = false
    do { try await manager.prepareForSignOut() } catch { XCTFail("Retry should succeed") }
    XCTAssertNil(manager.activeUserID)
  }
  func testNewAccountOptOutCleansOldInstallationWithoutRegisteringIt() async {
    let defaults = preferences()
    defaults.set(true, forKey: "push.optedIn.\(user.uuidString)")
    var removed = 0
    let manager = PushNotificationManager(
      preferences: defaults, permissionStatus: { .allowed }, installation: { self.installation },
      environment: { .sandbox },
      save: { _, _, _ in }, remove: { _ in removed += 1 }, registerWithAPNs: {},
      unregisterFromAPNs: {})
    await manager.synchronize(userID: user)
    await manager.receivedDeviceToken(Data([1]))
    await manager.synchronize(userID: UUID())
    XCTAssertEqual(removed, 1)
    XCTAssertFalse(manager.enabled)
    XCTAssertFalse(manager.registered)
  }
  func testAccountSwitchWaitsForInflightRegistrationBeforeCleanup() async {
    let defaults = preferences()
    defaults.set(true, forKey: "push.optedIn.\(user.uuidString)")
    var pending: CheckedContinuation<Void, Error>?
    var events: [String] = []
    let manager = PushNotificationManager(
      preferences: defaults, permissionStatus: { .allowed }, installation: { self.installation },
      environment: { .sandbox },
      save: { _, _, _ in
        events.append("upload")
        try await withCheckedThrowingContinuation { pending = $0 }
        events.append("uploaded")
      }, remove: { _ in events.append("removed") }, registerWithAPNs: {}, unregisterFromAPNs: {})
    await manager.synchronize(userID: user)
    let registration = Task { await manager.receivedDeviceToken(Data([1])) }
    while pending == nil { await Task.yield() }
    let replacement = Task { await manager.synchronize(userID: UUID()) }
    await Task.yield()
    XCTAssertEqual(events, ["upload"])
    pending?.resume(returning: ())
    await registration.value
    await replacement.value
    XCTAssertEqual(events, ["upload", "uploaded", "removed"])
    XCTAssertFalse(manager.registered)
  }

  func testTokenCallbackDuringLogoutCannotReregisterTheDevice() async throws {
    let defaults = preferences()
    defaults.set(true, forKey: "push.optedIn.\(user.uuidString)")
    var saves = 0
    var pending: CheckedContinuation<Void, Error>?
    let manager = PushNotificationManager(
      preferences: defaults, permissionStatus: { .allowed }, installation: { self.installation },
      environment: { .sandbox }, save: { _, _, _ in saves += 1 },
      remove: { _ in try await withCheckedThrowingContinuation { pending = $0 } },
      registerWithAPNs: {}, unregisterFromAPNs: {})
    await manager.synchronize(userID: user)
    await manager.receivedDeviceToken(Data([1]))
    let logout = Task { try await manager.prepareForSignOut() }
    while pending == nil { await Task.yield() }
    await manager.receivedDeviceToken(Data([2]))
    XCTAssertEqual(saves, 1)
    pending?.resume(returning: ())
    try await logout.value
    XCTAssertNil(manager.activeUserID)
  }

  func testColdTapWaitsForAuthAndReadIsConfirmedOnlyAfterOpening() async {
    let destination = destination()
    var marked = 0
    let manager = PushNotificationManager(
      preferences: preferences(), permissionStatus: { .denied },
      fetchNotification: { _ in self.notification(destination, user: self.user) },
      markRead: { _ in marked += 1 },
      registerWithAPNs: {}, unregisterFromAPNs: {})
    manager.received(destination, tapped: true)
    await manager.synchronize(userID: nil)
    XCTAssertEqual(manager.pendingDestination, destination)
    XCTAssertEqual(marked, 0)
    await manager.synchronize(userID: user)
    XCTAssertEqual(manager.presentedActivity, destination)
    XCTAssertEqual(marked, 0)
    await manager.confirmOpened(destination)
    XCTAssertEqual(marked, 1)
    manager.sessionEnded()
    XCTAssertNil(manager.presentedActivity)
    XCTAssertNil(manager.pendingDestination)
  }
  func testWrongRecipientAndDeletedNotificationCannotNavigate() async {
    for missing in [true, false] {
      let destination = destination()
      let manager = PushNotificationManager(
        preferences: preferences(), permissionStatus: { .denied },
        fetchNotification: { _ in missing ? nil : self.notification(destination, user: UUID()) },
        registerWithAPNs: {}, unregisterFromAPNs: {})
      manager.received(destination, tapped: true)
      await manager.synchronize(userID: user)
      XCTAssertNil(manager.presentedActivity)
      XCTAssertNotNil(manager.navigationError)
    }
  }
  func testForegroundPreservesLocalRemindersAndDoesNotMarkRemoteRead() async {
    XCTAssertTrue(
      PushNotificationManager.showsForegroundBanner(
        isRemote: false, validPayload: false, authenticated: false))
    XCTAssertFalse(
      PushNotificationManager.showsForegroundBanner(
        isRemote: true, validPayload: false, authenticated: true))
    XCTAssertFalse(
      PushNotificationManager.showsForegroundBanner(
        isRemote: true, validPayload: true, authenticated: false))
    let manager = PushNotificationManager(
      preferences: preferences(), permissionStatus: { .denied },
      markRead: { _ in XCTFail("Reception is not reading") },
      registerWithAPNs: {}, unregisterFromAPNs: {})
    manager.received(destination(), tapped: false)
    XCTAssertEqual(manager.refreshRevision, 1)
    XCTAssertNil(manager.pendingDestination)
  }
  func testSigningParserRejectsUnsignedAndTruncatedExecutables() {
    XCTAssertNil(SigningEntitlements.entitlements(in: Data()))
    XCTAssertNil(SigningEntitlements.entitlements(in: Data(repeating: 255, count: 128)))
    XCTAssertNil(SigningEntitlements.apnsEnvironment())  // unsigned XCTest host in simulator
  }
  func testSigningParserReadsActualEntitlementBlobWithoutDebugGuess() throws {
    let plist = try PropertyListSerialization.data(
      fromPropertyList: ["aps-environment": "production"], format: .xml, options: 0)
    var bytes = [UInt8](repeating: 0, count: 48)
    func write(_ value: UInt32, at: Int, big: Bool = false) {
      let parts = (0..<4).map { UInt8((value >> UInt32($0 * 8)) & 255) }
      bytes.replaceSubrange(at..<at + 4, with: big ? Array(parts.reversed()) : parts)
    }
    write(0xfeed_facf, at: 0)
    write(1, at: 16)
    write(0x1d, at: 32)
    write(16, at: 36)
    write(48, at: 40)
    let length = 20 + 8 + plist.count
    write(UInt32(length), at: 44)
    bytes += [UInt8](repeating: 0, count: 28)
    write(0xfade_0cc0, at: 48, big: true)
    write(UInt32(length), at: 52, big: true)
    write(1, at: 56, big: true)
    write(5, at: 60, big: true)
    write(20, at: 64, big: true)
    write(0xfade_7171, at: 68, big: true)
    write(UInt32(plist.count + 8), at: 72, big: true)
    bytes += plist
    XCTAssertEqual(
      SigningEntitlements.entitlements(in: Data(bytes))?["aps-environment"] as? String, "production"
    )
  }
}
