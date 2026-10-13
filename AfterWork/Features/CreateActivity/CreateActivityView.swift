import SwiftUI

struct CreateActivityView: View {
    var body: some View {
        NavigationStack {
            EmptyStateView(
                icon: "plus.circle.fill",
                title: "Bring people together",
                subtitle: "A place to plan an activity and invite coworkers will be here soon."
            )
            .navigationTitle("Create Activity")
        }
    }
}

#Preview {
    CreateActivityView()
}
