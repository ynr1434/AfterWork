import SwiftUI

struct FeedView: View {
    @Environment(ActivityListViewModel.self) private var model
    @State private var index = 0

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    Text("What's happening after work?")
                        .font(AppTypography.body).foregroundStyle(AppColors.secondaryText)
                        .padding(.horizontal, AppSpacing.lg)
                    CategoryFilter(selection: $model.selectedCategoryId, categories: model.categories)
                    if !model.visibleActivities.isEmpty {
                        let activities = model.visibleActivities
                        let activity = activities[min(index, activities.count - 1)]
                        VStack(spacing: AppSpacing.lg) {
                            NavigationLink {
                                ActivityDetailsView(id: activity.id)
                            } label: { ActivityCard(activity: activity) }
                                .buttonStyle(.plain)
                                .accessibilityHint("Opens activity details")
                            HStack(spacing: AppSpacing.lg) {
                                unavailableAction("Skip", symbol: "xmark", color: .secondary)
                                unavailableAction("Save", symbol: "bookmark", color: AppColors.accent)
                                unavailableAction("Going", symbol: "checkmark", color: .green)
                            }
                            Text("Joining, saving, and skipping are coming soon.")
                                .font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
                            HStack {
                                Button("Previous", systemImage: "chevron.left") { index = max(0, index - 1) }
                                    .disabled(index == 0)
                                Spacer()
                                Text("\(min(index + 1, activities.count)) of \(activities.count)")
                                    .font(AppTypography.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("Next", systemImage: "chevron.right") { index += 1 }
                                    .disabled(index >= activities.count - 1)
                            }
                        }.padding(.horizontal, AppSpacing.lg)
                    }
                    ActivityListStatusView()
                }
                .frame(maxWidth: 600).frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.md)
            }
            .refreshable { await model.load(refresh: true) }
            .background(AppColors.appBackground)
            .navigationTitle("AfterWork")
            .onChange(of: model.selectedCategoryId) { index = 0 }
            .onChange(of: model.activities.map(\.id)) { index = min(index, max(0, model.visibleActivities.count - 1)) }
        }
    }

    private func unavailableAction(_ title: String, symbol: String, color: Color) -> some View {
        Button {} label: {
            VStack(spacing: AppSpacing.sm) {
                Image(systemName: symbol).font(.title2.weight(.semibold))
                    .frame(width: 60, height: 60).background(color.opacity(0.15), in: Circle())
                Text(title).font(AppTypography.caption.weight(.semibold))
            }.frame(maxWidth: .infinity, minHeight: 44)
        }.buttonStyle(.plain).disabled(true).opacity(0.5)
            .accessibilityLabel("\(title), coming soon")
    }
}

#Preview {
    FeedView().environment(ActivityListViewModel()).environment(AuthManager())
}
