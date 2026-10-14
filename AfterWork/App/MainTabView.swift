import SwiftUI

struct MainTabView: View {
    @State private var activities = ActivityListViewModel()
    @State private var notifications = NotificationsViewModel()
    @Environment(PushNotificationManager.self) private var push
    @Environment(AuthManager.self) private var auth
    var body: some View {
        @Bindable var push = push
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

            NotificationsView(model: notifications)
                .tabItem {
                    Label("Notifications", systemImage: "bell.fill")
                }
                .badge(notifications.unreadCount)

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle.fill")
                }
        }
        .tint(AppColors.accent)
        .environment(activities)
        .task(id: push.refreshRevision) { await notifications.load() }
        .task(id: push.pendingDestination?.id) { await push.resolvePendingDestination() }
        .sheet(item: $push.presentedActivity) { destination in
            NavigationStack {
                ActivityDetailsView(id: destination.activityID)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { push.presentedActivity=nil } } }
                    .task { await push.confirmOpened(destination) }
            }.environment(activities)
        }
        .alert("Notification", isPresented: Binding(get:{push.navigationError != nil},set:{if !$0 {push.navigationError=nil}})) {
            if push.pendingDestination != nil {
                Button("Retry") { Task { await push.resolvePendingDestination() } }
            }
            Button("OK",role:.cancel) { push.navigationError=nil }
        } message: { Text(push.navigationError ?? "") }
        .task(id: "\(activities.selectedCategoryId?.uuidString ?? "all")-\(activities.revision)") {
            await activities.load(refresh: true)
        }
        .onChange(of: activities.needsAuthentication) { _, needed in
            if needed { Task { await auth.restore() } }
        }
    }
}

#Preview {
    MainTabView().environment(AuthManager()).environment(PushNotificationManager.shared)
}
