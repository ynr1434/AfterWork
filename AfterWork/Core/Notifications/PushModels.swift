import Foundation

nonisolated enum APNsEnvironment: String, Codable, Sendable {
  case sandbox, production
  init?(entitlement: String?) {
    switch entitlement {
    case "development": self = .sandbox
    case "production": self = .production
    default: return nil
    }
  }
}

nonisolated enum PushToken {
  static func normalize(_ data: Data) -> String? {
    guard !data.isEmpty, data.count <= 256 else { return nil }
    return data.map { String(format: "%02x", $0) }.joined()
  }
}

nonisolated struct PushDestination: Equatable, Sendable, Identifiable {
  let notificationID: UUID
  let activityID: UUID
  let type: String
  var id: UUID { notificationID }

  init?(userInfo: [AnyHashable: Any]) {
    guard let notification = userInfo["notification_id"] as? String,
      let activity = userInfo["activity_id"] as? String,
      let notificationID = UUID(uuidString: notification),
      let activityID = UUID(uuidString: activity),
      let type = userInfo["type"] as? String, ["mention", "activityComment"].contains(type)
    else { return nil }
    self.notificationID = notificationID
    self.activityID = activityID
    self.type = type
  }
}

nonisolated enum PushPermission: Equatable {
  case notDetermined, allowed, denied, unsupported
  var title: String {
    switch self {
    case .notDetermined: "Not enabled"
    case .allowed: "Allowed by iOS"
    case .denied: "Disabled in iOS Settings"
    case .unsupported: "Unavailable"
    }
  }
}

nonisolated enum PushError: Error, LocalizedError {
  case installation, unavailable, registration, cleanup
  var errorDescription: String? {
    switch self {
    case .installation: "We couldn't prepare this device for push notifications. Please try again."
    case .unavailable:
      "Push requires a properly provisioned app with the Push Notifications entitlement."
    case .registration: "We couldn't register notifications on this device. Please retry."
    case .cleanup:
      "We couldn't remove this device's push registration. Check your connection and retry signing out."
    }
  }
}
