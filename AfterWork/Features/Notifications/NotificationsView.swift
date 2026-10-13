import SwiftUI

struct NotificationsView: View {
    @Bindable var model: NotificationsViewModel

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoading && model.notifications.isEmpty { ProgressView("Loading notifications…") }
                else if model.notifications.isEmpty {
                    EmptyStateView(icon: "bell.badge", title: "No notifications yet", subtitle: "Mentions and activity comments will appear here.")
                } else {
                    List(model.notifications) { notification in
                        notificationRow(notification)
                            .listRowBackground(notification.isRead ? Color.clear : AppColors.secondarySurface)
                    }.listStyle(.plain)
                }
            }
            .navigationTitle("Notifications")
            .toolbar {
                if model.unreadCount > 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Mark all read") { Task { await model.markAllRead() } }
                    }
                }
            }
            .task { await model.load() }
            .refreshable { await model.load() }
            .overlay(alignment: .bottom) {
                if let error = model.errorMessage { Text(error).font(.footnote).foregroundStyle(.red).padding() }
            }
        }
    }

    @ViewBuilder private func notificationRow(_ notification: AppNotification) -> some View {
        if let activityID = notification.activityID {
            NavigationLink { ActivityDetailsView(id: activityID).onAppear { Task { await model.markRead(notification) } } } label: {
                rowContent(notification)
            }
        } else {
            rowContent(notification).onAppear { Task { await model.markRead(notification) } }
        }
    }

    private func rowContent(_ notification: AppNotification) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Image(systemName: notification.kind == .mention ? "at" : "text.bubble.fill")
                .foregroundStyle(AppColors.accent).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(notification.title).font(.headline)
                Text(notification.body).font(.subheadline).foregroundStyle(.secondary)
                Text(notification.createdAt.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !notification.isRead { Circle().fill(AppColors.accent).frame(width: 8, height: 8) }
        }.padding(.vertical, 6)
    }
}

#Preview { NotificationsView(model: NotificationsViewModel()) }
