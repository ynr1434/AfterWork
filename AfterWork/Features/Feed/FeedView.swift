import SwiftUI

struct FeedView: View {
    var body: some View {
        NavigationStack {
            EmptyStateView(
                icon: "rectangle.stack.fill",
                title: "Plans start here",
                subtitle: "Discover activities to enjoy with coworkers after work."
            )
            .navigationTitle("Feed")
        }
    }
}

#Preview {
    FeedView()
}
