import SwiftUI

struct ExploreView: View {
    var body: some View {
        NavigationStack {
            EmptyStateView(
                icon: "safari.fill",
                title: "Find your next activity",
                subtitle: "Explore new ways to spend time together after work."
            )
            .navigationTitle("Explore")
        }
    }
}

#Preview {
    ExploreView()
}
