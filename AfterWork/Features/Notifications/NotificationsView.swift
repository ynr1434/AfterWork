import SwiftUI

struct NotificationsView: View {
    @Bindable var model: NotificationsViewModel

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoading && model.notifications.isEmpty { LoadingView(title: "Loading notifications…") }
                else if model.notifications.isEmpty && model.errorMessage == nil {
                    EmptyStateView(icon: "bell.badge", title: "You're in the loop", subtitle: "Mentions and comments on your activities will appear here.")
                } else {
                    List(model.notifications) { notification in
                        notificationRow(notification)
                            .listRowBackground(notification.isRead ? AppColors.surface : AppColors.accent.opacity(0.06))
                    }.listStyle(.insetGrouped).scrollContentBackground(.hidden)
                }
            }
            .background(AppColors.appBackground)
            .navigationTitle("Notifications")
            .toolbar {
                if model.unreadCount > 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { Task { await model.markAllRead() } } label: {
                            if model.isMarkingAll { ProgressView() }
                            else { Image(systemName: "checkmark.circle").frame(minWidth: 44, minHeight: 44) }
                        }.disabled(model.isMarkingAll || model.isLoading).accessibilityLabel("Mark all notifications as read")
                    }
                }
            }
            .task { await model.load() }
            .refreshable { await model.load() }
            .safeAreaInset(edge: .bottom) {
                if let error = model.errorMessage {
                    InlineMessage(message: error) { Task { await model.load() } }
                        .disabled(model.isLoading).padding(.horizontal).padding(.bottom, AppSpacing.sm)
                }
            }
        }
    }

    @ViewBuilder private func notificationRow(_ notification: AppNotification) -> some View {
        if let activityID = notification.activityID {
            NavigationLink { ActivityDetailsView(id: activityID).task { await model.markRead(notification) } } label: {
                rowContent(notification)
            }
        } else {
            Button { Task { await model.markRead(notification) } } label: {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    rowContent(notification)
                    Text("This activity is no longer available.").font(.caption).foregroundStyle(.secondary)
                }
            }.buttonStyle(.plain).accessibilityHint("Mark this notification as read")
        }
    }

    private func rowContent(_ notification: AppNotification) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Image(systemName: notification.kind == .mention ? "at" : "text.bubble.fill")
                .font(.headline).foregroundStyle(AppColors.accent).frame(width: 36, height: 36)
                .background(AppColors.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: AppCornerRadius.small))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                if !notification.isRead {
                    Label("Unread", systemImage: "circle.fill").font(.caption2.bold()).foregroundStyle(AppColors.accent)
                }
                Text(notification.title).font(.headline)
                Text(notification.body).font(.subheadline).foregroundStyle(.secondary)
                Text(notification.createdAt, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
            }.fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, AppSpacing.sm)
    }
}

#Preview { NotificationsView(model: NotificationsViewModel()) }
