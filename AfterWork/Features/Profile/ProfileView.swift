import SwiftUI

struct ProfileView: View {
    var body: some View {
        NavigationStack {
            EmptyStateView(
                icon: "person.crop.circle.fill",
                title: "Your AfterWork profile",
                subtitle: "Your profile and preferences will have a home here."
            )
            .navigationTitle("Profile")
        }
    }
}

#Preview {
    ProfileView()
}
