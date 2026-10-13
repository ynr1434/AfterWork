import SwiftUI

struct MainTabView: View {
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
    }
}

#Preview {
    MainTabView()
}
