import SwiftUI

struct FeedView: View {
    @Environment(ActivityListViewModel.self) private var model
    @Environment(AuthManager.self) private var auth
    @State private var engagement = ActivityEngagementViewModel()
    @State private var index = 0

    private var feedActivities: [Activity] {
        EngagementRules.feedActivities(model.visibleActivities.map { engagement.state(for: $0) })
    }
    private var currentIndex: Int { min(index, max(0, feedActivities.count - 1)) }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    Text("Your next good plan starts here.")
                        .foregroundStyle(AppColors.secondaryText).padding(.horizontal, AppSpacing.lg)
                    CategoryFilter(selection: $model.selectedCategoryId, categories: model.categories)
                    if !feedActivities.isEmpty {
                        let activity = feedActivities[currentIndex]
                        VStack(spacing: AppSpacing.md) {
                            SwipeActivityCard(activity: activity, isBusy: engagement.isBusy) { action in
                                await handle(action, activity: activity, advance: action == .save)
                            }.id(activity.id)
                            HStack(alignment: .top, spacing: AppSpacing.sm) {
                                actionButton("Skip", symbol: "xmark", color: .secondary) {
                                    Task { await handle(.skip, activity: activity) }
                                }
                                actionButton(activity.isSaved ? "Saved" : "Save", symbol: activity.isSaved ? "bookmark.fill" : "bookmark", color: AppColors.accent) {
                                    Task { await handle(activity.isSaved ? .unsave : .save, activity: activity) }
                                }
                                let isOrganizer = activity.authorId == auth.userID
                                let isFull = activity.maxParticipants.map { activity.participantCount >= $0 } ?? false
                                actionButton(isOrganizer ? "Organizer" : activity.isGoing ? "Going" : isFull ? "Full" : "Join",
                                             symbol: isOrganizer || activity.isGoing ? "checkmark.circle.fill" : "person.badge.plus", color: AppColors.accent) {
                                    Task { await handle(activity.isGoing ? .leave : .join, activity: activity) }
                                }.disabled(isOrganizer || (isFull && !activity.isGoing))
                            }.disabled(engagement.isBusy)
                            HStack {
                                Button { index = max(0, currentIndex - 1) } label: {
                                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                                }.disabled(currentIndex == 0).accessibilityLabel("Previous activity")
                                Spacer()
                                Text(EngagementRules.positionText(index: currentIndex, count: feedActivities.count))
                                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                                Spacer()
                                Button { index = currentIndex + 1 } label: {
                                    Image(systemName: "chevron.right").frame(width: 44, height: 44)
                                }.disabled(currentIndex >= feedActivities.count - 1).accessibilityLabel("Next activity")
                            }.disabled(engagement.isBusy)
                        }.padding(.horizontal, AppSpacing.lg)
                    } else if model.hasLoaded && !model.visibleActivities.isEmpty && model.errorMessage == nil {
                        EmptyStateContent(icon: "checkmark.circle", title: "You're all caught up", subtitle: "You've skipped the available plans. Explore other categories or check back for something new.")
                    }
                    if engagement.isBusy { ProgressView("Updating activity…").frame(maxWidth: .infinity) }
                    if let error = engagement.errorMessage { InlineMessage(message: error).padding(.horizontal, AppSpacing.lg) }
                    ActivityListStatusView()
                }
                .frame(maxWidth: 600).frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.md)
            }
            .refreshable { await refresh() }
            .background(AppColors.appBackground)
            .navigationTitle("AfterWork")
            .onChange(of: model.selectedCategoryId) { index = 0 }
            .onChange(of: feedActivities.map(\.id)) { index = currentIndex }
            .task { await model.load(); await engagement.load(activityIDs: model.activities.map(\.id)) }
        }
        .onChange(of: engagement.needsAuthentication) { _, needed in
            if needed { Task { await auth.restore() } }
        }
    }

    enum Action: Equatable { case save, unsave, skip, join, leave }

    private func refresh() async {
        await model.load(refresh: true)
        await engagement.load(activityIDs: model.activities.map(\.id))
    }

    private func handle(_ action: Action, activity: Activity, advance: Bool = false) async {
        guard !engagement.isBusy else { return }
        let previousIndex = currentIndex
        switch action {
        case .save: await engagement.save(activityId: activity.id, isSaved: true)
        case .unsave: await engagement.save(activityId: activity.id, isSaved: false)
        case .skip: await engagement.skip(activityId: activity.id)
        case .join: await engagement.join(activityId: activity.id)
        case .leave: await engagement.leave(activityId: activity.id, organizerID: activity.authorId)
        }
        guard engagement.errorMessage == nil else { return }
        model.applyEngagement(engagement.states)
        // Removing a skipped card already moves its successor into the same index.
        index = EngagementRules.nextIndex(after: action, index: previousIndex, remainingCount: feedActivities.count, advanceSaved: advance)
    }

    private func actionButton(_ title: String, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.sm) {
                Image(systemName: symbol).font(.title2.weight(.semibold))
                    .frame(width: 56, height: 56).background(color.opacity(0.12), in: Circle())
                Text(title).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain).foregroundStyle(color)
        .accessibilityLabel(title)
        .accessibilityHint(title == "Going" ? "Leave this activity" : "")
        .opacity(engagement.isBusy ? 0.5 : 1)
    }
}

private struct SwipeActivityCard: View {
    let activity: Activity
    let isBusy: Bool
    let action: (FeedView.Action) async -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var translation: CGFloat = 0
    @State private var committed = false

    var body: some View {
        ZStack {
            NavigationLink { ActivityDetailsView(id: activity.id) } label: {
                ActivityCard(activity: activity)
            }.buttonStyle(.plain).disabled(committed || isBusy)
            HStack {
                swipeLabel("SKIP", symbol: "xmark").opacity(translation < -20 ? 1 : 0)
                Spacer()
                swipeLabel("SAVE", symbol: "bookmark.fill").opacity(translation > 20 ? 1 : 0)
            }.padding(AppSpacing.lg).allowsHitTesting(false).accessibilityHidden(true)
        }
        .offset(x: reduceMotion ? 0 : translation * 0.45)
        .rotationEffect(.degrees(reduceMotion ? 0 : Double(translation / 60)))
        .simultaneousGesture(DragGesture(minimumDistance: 24).onChanged { value in
            guard !committed, !isBusy, abs(value.translation.width) > abs(value.translation.height) else { return }
            translation = value.translation.width
        }.onEnded { value in
            guard !committed, !isBusy else { return }
            guard abs(value.translation.width) > abs(value.translation.height),
                  let swipe = EngagementRules.swipeAction(for: value.translation.width) else { reset(); return }
            committed = true
            Task {
                await action(swipe == .save ? .save : .skip)
                reset()
                committed = false
            }
        })
        .accessibilityHint("Opens activity details. Save and Skip buttons are below the card.")
    }

    private func reset() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { translation = 0 }
    }
    private func swipeLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.headline.bold()).foregroundStyle(AppColors.primaryText)
            .padding(.horizontal, AppSpacing.md).padding(.vertical, AppSpacing.sm)
            .background(.regularMaterial, in: Capsule())
    }
}

#Preview { FeedView().environment(ActivityListViewModel()).environment(AuthManager()) }
