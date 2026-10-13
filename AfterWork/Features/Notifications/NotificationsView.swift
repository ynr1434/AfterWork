import SwiftUI

struct NotificationsView: View {
    var body: some View {
        NavigationStack {
            EmptyStateView(
                icon: "bell.fill",
                title: "Stay in the loop",
                subtitle: "Updates about your activities will appear here."
            )
            .navigationTitle("Notifications")
        }
    }
}

#Preview {
    NotificationsView()
}
