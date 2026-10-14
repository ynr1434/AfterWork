import SwiftUI
import UIKit

struct PushSettingsView: View {
  @Environment(PushNotificationManager.self) private var push
  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.sm) {
      Text("Notifications").font(AppTypography.headline)
      Text(
        "Push Notifications: \(push.permission == .denied ? "Disabled" : push.registered ? "Enabled" : push.enabled ? "Finishing setup" : "Off")"
      )
      Text(push.permission.title).font(AppTypography.caption).foregroundStyle(.secondary)
      Text("Get alerts for mentions and comments on your activities.").font(AppTypography.caption)
        .foregroundStyle(.secondary)
      if push.permission == .denied {
        Text("Allow notifications for AfterWork in iOS Settings.").font(AppTypography.caption)
        Button("Open Settings") {
          if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
          }
        }
      } else {
        Button(push.registered ? "Refresh Status" : push.enabled ? "Try Again" : "Enable Notifications") {
          Task { await push.enable() }
        }
        .disabled(push.isWorking)
      }
      if push.enabled {
        Button("Turn Off Push", role: .destructive) { Task { await push.disable() } }.disabled(
          push.isWorking)
      }
      if push.isWorking { ProgressView("Updating notifications…") }
      if let message = push.message {
        Text(message).font(AppTypography.caption).foregroundStyle(.secondary)
      }
    }.buttonStyle(.bordered).controlSize(.large)
      .frame(maxWidth: .infinity, alignment: .leading)
      .task { await push.updatePermission() }
  }
}
