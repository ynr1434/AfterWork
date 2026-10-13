import SwiftUI

struct MainTabView: View {
    @State private var activities = ActivityListViewModel()
    @Environment(AuthManager.self) private var auth
    var body: some View {
        TabView {
            FeedView()
                .tabItem {
                    Label("Feed", systemImage: "rectangle.stack.fill")
                }

            ExploreView()
                .tabItem {
                    Label("Explore", systemImage: "safari.fill")
                }

            CreateActivityView()
                .tabItem {
                    Label("Create", systemImage: "plus.circle.fill")
                }

            NotificationsView()
                .tabItem {
                    Label("Notifications", systemImage: "bell.fill")
                }

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle.fill")
                }
        }
        .tint(AppColors.accent)
        .environment(activities)
        .task(id: "\(activities.selectedCategoryId?.uuidString ?? "all")-\(activities.revision)") {
            await activities.load(refresh: true)
        }
        .onChange(of: activities.needsAuthentication) { _, needed in
            if needed { Task { await auth.restore() } }
        }
    }
}

#Preview {
    MainTabView().environment(AuthManager())
}
