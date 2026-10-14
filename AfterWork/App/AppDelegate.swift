import UIKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return true  // Permission/registration are deliberately not requested here.
  }
  func application(
    _ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Task { await PushNotificationManager.shared.receivedDeviceToken(deviceToken) }
  }
  func application(
    _ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    PushNotificationManager.shared.registrationFailed()  // Never log raw tokens or errors.
  }
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    let isRemote = notification.request.trigger is UNPushNotificationTrigger
    let destination =
      isRemote ? PushDestination(userInfo: notification.request.content.userInfo) : nil
    return await MainActor.run {
      let manager = PushNotificationManager.shared
      if isRemote { manager.received(destination, tapped: false) }
      return PushNotificationManager.showsForegroundBanner(
        isRemote: isRemote, validPayload: destination != nil,
        authenticated: manager.activeUserID != nil && manager.enabled) ? [.banner, .sound] : []
    }
  }
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
  ) async {
    guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
      response.notification.request.trigger is UNPushNotificationTrigger
    else { return }
    let destination = PushDestination(userInfo: response.notification.request.content.userInfo)
    await MainActor.run { PushNotificationManager.shared.received(destination, tapped: true) }
  }
}
