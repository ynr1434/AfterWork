import SwiftUI

struct FeedView: View {
    @Environment(ActivityListViewModel.self) private var model
    @Environment(AuthManager.self) private var auth
    @State private var engagement = ActivityEngagementViewModel()
    @State private var index = 0

    private var feedActivities: [Activity] {
        EngagementRules.feedActivities(model.visibleActivities.map { engagement.state(for: $0) })
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    Text("What's happening after work?")
                        .font(AppTypography.body).foregroundStyle(AppColors.secondaryText)
                        .padding(.horizontal, AppSpacing.lg)
                    CategoryFilter(selection: $model.selectedCategoryId, categories: model.categories)
                    if !feedActivities.isEmpty {
                        let activity = feedActivities[min(index, feedActivities.count - 1)]
                        VStack(spacing: AppSpacing.lg) {
                            SwipeActivityCard(activity: activity) { action in
                                Task {
                                    await handle(action, activity: activity)
                                    if action == .save { index += 1 }
                                }
                            }.id(activity.id)
                            HStack(spacing: AppSpacing.lg) {
                                actionButton("Skip", symbol: "xmark", color: .secondary) {
                                    Task { await handle(.skip, activity: activity) }
                                }
                                actionButton(activity.isSaved ? "Saved" : "Save", symbol: activity.isSaved ? "bookmark.fill" : "bookmark", color: AppColors.accent) {
                                    Task { await handle(activity.isSaved ? .unsave : .save, activity: activity) }
                                }
                                actionButton(activity.isGoing ? "Going" : "I'm Going", symbol: activity.isGoing ? "checkmark.circle.fill" : "checkmark", color: .green) {
                                    Task { await handle(activity.isGoing ? .leave : .join, activity: activity) }
                                }
                            }
                            HStack {
                                Button("Previous", systemImage: "chevron.left") { index = max(0, index - 1) }
                                    .disabled(index == 0)
                                Spacer()
                                Text("(min(index + 1, feedActivities.count)) of (feedActivities.count)")
                                    .font(AppTypography.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("Next", systemImage: "chevron.right") { index += 1 }
                                    .disabled(index >= feedActivities.count - 1)
                            }
                        }.padding(.horizontal, AppSpacing.lg)
                    }
                    if let error = engagement.errorMessage { Text(error).foregroundStyle(.red).padding(.horizontal, AppSpacing.lg) }
                    ActivityListStatusView()
                }
                .frame(maxWidth: 600).frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.md)
            }
            .refreshable {
                await model.load(refresh: true)
                await engagement.load(activityIDs: model.activities.map(\.id))
            }
            .background(AppColors.appBackground)
            .navigationTitle("AfterWork")
            .onChange(of: model.selectedCategoryId) { index = 0 }
            .onChange(of: model.activities.map(\.id)) { index = min(index, max(0, feedActivities.count - 1)) }
            .task {
                await model.load()
                await engagement.load(activityIDs: model.activities.map(\.id))
            }
        }
        .onChange(of: engagement.needsAuthentication) { _, needed in
            if needed { Task { await auth.restore() } }
        }
    }

    enum Action: Equatable { case save, unsave, skip, join, leave }

    private func handle(_ action: Action, activity: Activity) async {
        switch action {
        case .save: await engagement.save(activityId: activity.id, isSaved: true)
        case .unsave: await engagement.save(activityId: activity.id, isSaved: false)
        case .skip: await engagement.skip(activityId: activity.id)
        case .join: await engagement.join(activityId: activity.id)
        case .leave: await engagement.leave(activityId: activity.id)
        }
        if action == .skip { index += 1 }
        index = min(index, max(0, feedActivities.count - 1))
    }

    private func actionButton(_ title: String, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.sm) {
                Image(systemName: symbol).font(.title2.weight(.semibold))
                    .frame(width: 60, height: 60).background(color.opacity(0.15), in: Circle())
                Text(title).font(AppTypography.caption.weight(.semibold))
            }.frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct SwipeActivityCard: View {
    let activity: Activity
    let action: (FeedView.Action) -> Void
    @State private var translation: CGFloat = 0
    @State private var committed = false

    var body: some View {
        ZStack {
            NavigationLink { ActivityDetailsView(id: activity.id) } label: {
                ActivityCard(activity: activity)
            }.buttonStyle(.plain)
            HStack {
                swipeLabel("SKIP", symbol: "xmark", color: .secondary).opacity(translation < 0 ? 1 : 0)
                Spacer()
                swipeLabel("SAVE", symbol: "bookmark.fill", color: AppColors.accent).opacity(translation > 0 ? 1 : 0)
            }
            .padding(AppSpacing.lg)
            .allowsHitTesting(false)
        }
        .offset(x: translation)
        .rotationEffect(.degrees(Double(translation / 30)))
        .gesture(DragGesture().onChanged { value in
            guard !committed else { return }
            translation = value.translation.width
        }.onEnded { value in
            guard !committed else { return }
            guard let swipeAction = EngagementRules.swipeAction(for: value.translation.width) else {
                withAnimation(.spring) { translation = 0 }
                return
            }
            committed = true
            let swipeRight = swipeAction == .save
            withAnimation(.easeIn(duration: 0.2)) { translation = swipeRight ? 700 : -700 }
            action(swipeRight ? .save : .skip)
        })
        .accessibilityHint("Swipe left to skip or right to save")
    }

    private func swipeLabel(_ title: String, symbol: String, color: Color) -> some View {
        Label(title, systemImage: symbol).font(.headline.bold()).foregroundStyle(color)
            .padding(.horizontal, AppSpacing.md).padding(.vertical, AppSpacing.sm)
            .background(.thinMaterial, in: Capsule())
    }
}

#Preview { FeedView().environment(ActivityListViewModel()).environment(AuthManager()) }
