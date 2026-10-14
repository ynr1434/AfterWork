import Foundation
import Observation
import UIKit
import UserNotifications

@MainActor @Observable
final class PushNotificationManager {
  static let shared = PushNotificationManager()
  private(set) var permission: PushPermission = .notDetermined
  private(set) var enabled = false
  private(set) var registered = false
  private(set) var isWorking = false
  private(set) var message: String?
  private(set) var pendingDestination: PushDestination?
  var presentedActivity: PushDestination?
  var navigationError: String?
  private(set) var refreshRevision = 0
  private(set) var activeUserID: UUID?
  @ObservationIgnored private var token: String?
  @ObservationIgnored private var generation = UUID()
  @ObservationIgnored private var upload: Task<Void, Never>?
  @ObservationIgnored private var resolving = false
  @ObservationIgnored private var removingRegistration = false
  @ObservationIgnored private let permissionStatus: () async -> PushPermission
  @ObservationIgnored private let requestPermission: () async throws -> Bool
  @ObservationIgnored private let preferences: UserDefaults
  @ObservationIgnored private let installation: () throws -> PushInstallation
  @ObservationIgnored private let environment: () -> APNsEnvironment?
  @ObservationIgnored private let save:
    (PushInstallation, String, APNsEnvironment) async throws -> Void
  @ObservationIgnored private let remove: (PushInstallation) async throws -> Void
  @ObservationIgnored private let fetchNotification: (UUID) async throws -> AppNotification?
  @ObservationIgnored private let markRead: (UUID) async throws -> Void
  @ObservationIgnored private let registerWithAPNs: @MainActor () -> Void
  @ObservationIgnored private let unregisterFromAPNs: @MainActor () -> Void

  init(
    preferences: UserDefaults = .standard,
    permissionStatus: @escaping () async -> PushPermission = {
      PushNotificationManager.mapPermission(
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus)
    },
    requestPermission: @escaping () async throws -> Bool = {
      try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    },
    installation: @escaping () throws -> PushInstallation = { try PushInstallation.load() },
    environment: @escaping () -> APNsEnvironment? = { SigningEntitlements.apnsEnvironment() },
    save: @escaping (PushInstallation, String, APNsEnvironment) async throws -> Void = {
      installation, token, environment in
      try await PushDeviceRepository(client: SupabaseManager.shared.client).register(
        installation: installation, token: token, environment: environment)
    },
    remove: @escaping (PushInstallation) async throws -> Void = { installation in
      try await PushDeviceRepository(client: SupabaseManager.shared.client).unregister(
        installation: installation)
    },
    fetchNotification: @escaping (UUID) async throws -> AppNotification? = { id in
      try await NotificationRepository(client: SupabaseManager.shared.client).fetchNotification(
        id: id)
    },
    markRead: @escaping (UUID) async throws -> Void = { id in
      try await NotificationRepository(client: SupabaseManager.shared.client).markAsRead(
        notificationID: id)
    },
    registerWithAPNs: @escaping @MainActor () -> Void = {
      UIApplication.shared.registerForRemoteNotifications()
    },
    unregisterFromAPNs: @escaping @MainActor () -> Void = {
      UIApplication.shared.unregisterForRemoteNotifications()
    }
  ) {
    self.permissionStatus = permissionStatus
    self.requestPermission = requestPermission
    self.preferences = preferences
    self.installation = installation
    self.environment = environment
    self.save = save
    self.remove = remove
    self.fetchNotification = fetchNotification
    self.markRead = markRead
    self.registerWithAPNs = registerWithAPNs
    self.unregisterFromAPNs = unregisterFromAPNs
  }

  private var mayHaveRegistration: Bool {
    get { preferences.bool(forKey: "push.registrationPossible") }
    set { preferences.set(newValue, forKey: "push.registrationPossible") }
  }
  private func preferenceKey(_ userID: UUID) -> String { "push.optedIn.\(userID.uuidString)" }

  func synchronize(userID: UUID?) async {
    if activeUserID != userID {
      generation = UUID()
      registered = false
      if activeUserID != nil {
        pendingDestination = nil
        presentedActivity = nil
      }
      activeUserID = userID
    }
    await upload?.value  // A new account's cleanup/registration follows every old upload.
    guard !removingRegistration, activeUserID == userID, let userID else { return }
    enabled = preferences.bool(forKey: preferenceKey(userID))
    await updatePermission()
    if enabled, permission == .allowed {
      if environment() != nil {
        registerWithAPNs()  // Always ask APNs for its current token; never persist/cache one.
        await uploadToken()
      } else {
        message = PushError.unavailable.localizedDescription
      }
    } else if mayHaveRegistration {
      do {
        try await remove(installation())
        mayHaveRegistration = false
        registered = false
      } catch { message = "Device cleanup is pending. Check your connection and retry." }
    }
    await resolvePendingDestination()
  }

  func updatePermission() async {
    permission = await permissionStatus()
  }
  nonisolated static func mapPermission(_ status: UNAuthorizationStatus) -> PushPermission {
    switch status {
    case .notDetermined: .notDetermined
    case .authorized, .provisional, .ephemeral: .allowed
    case .denied: .denied
    @unknown default: .unsupported
    }
  }

  func enable() async {
    guard let user = activeUserID, !isWorking else { return }
    guard environment() != nil else {
      message = PushError.unavailable.localizedDescription
      return
    }
    isWorking = true
    message = nil
    defer { isWorking = false }
    do {
      if permission == .notDetermined {
        _ = try await requestPermission()
      }
      await updatePermission()
      guard activeUserID == user else { return }
      guard permission == .allowed else {
        message = "Enable notifications for AfterWork in iOS Settings."
        return
      }
      preferences.set(true, forKey: preferenceKey(user))
      enabled = true
      registerWithAPNs()
      await uploadToken()
    } catch { message = PushError.registration.localizedDescription }
  }

  func disable() async {
    guard let user = activeUserID, !isWorking else { return }
    isWorking = true
    removingRegistration = true
    defer {
      isWorking = false
      removingRegistration = false
    }
    await upload?.value
    do {
      if mayHaveRegistration { try await remove(installation()) }
      mayHaveRegistration = false
      registered = false
      enabled = false
      preferences.set(false, forKey: preferenceKey(user))
      unregisterFromAPNs()
      message = nil
    } catch { message = PushError.cleanup.localizedDescription }
  }

  func receivedDeviceToken(_ data: Data) async {
    guard let normalized = PushToken.normalize(data) else {
      registrationFailed()
      return
    }
    token = normalized
    await uploadToken()
  }
  func registrationFailed() {
    registered = false
    message = PushError.registration.localizedDescription
  }

  private func uploadToken() async {
    while let upload {
      await upload.value
      await Task.yield()
    }
    guard !removingRegistration, let user = activeUserID, enabled, let token,
      let environment = environment()
    else {
      return
    }
    let version = generation
    let operation = Task { [weak self, installation, save] in
      guard let self else { return }
      defer { self.upload = nil }
      guard !self.removingRegistration, self.generation == version, self.activeUserID == user else {
        return
      }
      self.mayHaveRegistration = true  // Persist before the request to cover crash/response loss.
      do {
        try await save(installation(), token, environment)
        guard self.generation == version, self.activeUserID == user else { return }
        self.registered = true
        self.message = nil
      } catch {
        guard self.generation == version else { return }
        self.registered = false
        self.message = PushError.registration.localizedDescription
      }
    }
    upload = operation
    await operation.value
  }

  /// Fail closed: do not clear the authenticated session if its registration cannot
  /// be removed. Other devices are untouched; user can retry once connectivity returns.
  func prepareForSignOut() async throws {
    removingRegistration = true
    defer { removingRegistration = false }
    generation = UUID()
    await upload?.value
    if mayHaveRegistration {
      do {
        try await remove(installation())
        mayHaveRegistration = false
      } catch {
        message = PushError.cleanup.localizedDescription
        throw PushError.cleanup
      }
    }
    sessionEnded()
  }

  func sessionEnded() {
    generation = UUID()
    activeUserID = nil
    registered = false
    enabled = false
    token = nil
    pendingDestination = nil
    presentedActivity = nil
    navigationError = nil
    unregisterFromAPNs()
    refreshRevision += 1
  }

  func received(_ destination: PushDestination?, tapped: Bool) {
    guard let destination else { return }
    refreshRevision += 1  // Receiving a push is not proof it was read.
    if tapped {
      pendingDestination = destination
      navigationError = nil
    }
  }

  func resolvePendingDestination() async {
    guard !resolving, let user = activeUserID, let destination = pendingDestination else { return }
    resolving = true
    defer { resolving = false }
    do {
      let notification = try await fetchNotification(destination.notificationID)
      guard activeUserID == user, pendingDestination == destination else { return }
      guard let notification, notification.userID == user,
        notification.activityID == destination.activityID,
        notification.kind.rawValue == destination.type
      else {
        pendingDestination = nil
        navigationError = "This notification is no longer available for this account."
        return
      }
      presentedActivity = destination
      pendingDestination = nil
    } catch {
      guard activeUserID == user else { return }
      navigationError = "We couldn't open this notification. Check your connection and retry."
    }
  }

  func confirmOpened(_ destination: PushDestination) async {
    guard let user = activeUserID, presentedActivity == destination else { return }
    do {
      try await markRead(destination.notificationID)
      guard activeUserID == user else { return }
      refreshRevision += 1
    } catch {
      navigationError =
        "Activity opened, but its notification could not be marked read. Please retry in Notifications."
    }
  }

  static func showsForegroundBanner(isRemote: Bool, validPayload: Bool, authenticated: Bool) -> Bool
  {
    !isRemote || (validPayload && authenticated)
  }
}
