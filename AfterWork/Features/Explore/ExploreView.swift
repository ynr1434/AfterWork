import SwiftUI

struct ExploreView: View {
    @Environment(ActivityListViewModel.self) private var model
    @Environment(\.calendar) private var calendar

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    Text("Good company. New plans.")
                        .font(AppTypography.body).foregroundStyle(AppColors.secondaryText)
                        .padding(.horizontal, AppSpacing.lg)
                    CategoryFilter(selection: $model.selectedCategoryId, categories: model.categories)
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        LazyVStack(alignment: .leading, spacing: AppSpacing.lg) {
                            ForEach(ActivityDayGroup.allCases) { group in
                                let activities = model.visibleActivities.filter {
                                    ActivityDayGroup.group(for: $0.startsAt, now: context.date, calendar: calendar) == group
                                }
                                if !activities.isEmpty {
                                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                                        Text(group.rawValue).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                                        ForEach(activities) { activity in
                                            NavigationLink { ActivityDetailsView(id: activity.id) } label: {
                                                ActivityRow(activity: activity)
                                            }.buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }.padding(.horizontal, AppSpacing.lg)
                    }
                    ActivityListStatusView()
                }.frame(maxWidth: 700).frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.md)
            }
            .refreshable { await model.load(refresh: true) }
            .background(AppColors.appBackground)
            .navigationTitle("Explore")
        }
    }
}

#Preview { ExploreView().environment(ActivityListViewModel()).environment(AuthManager()) }
