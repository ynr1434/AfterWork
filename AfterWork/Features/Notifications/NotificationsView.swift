import SwiftUI

struct NotificationsView: View {
    var body: some View {
        NavigationStack {
            EmptyStateView(
                icon: "bell.badge",
                title: "No notifications yet",
                subtitle: "Invites, comments and activity updates will appear here."
            )
            .navigationTitle("Notifications")
        }
    }
}

#Preview { NotificationsView() }
