import SwiftUI

struct ExploreView: View {
    @State private var category: ActivityCategory?

    private var activities: [Activity] {
        MockActivities.activities.filter { category == nil || $0.category == category }
            .sorted { $0.startsAt < $1.startsAt }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    Text("Good company. New plans.")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.secondaryText)
                        .padding(.horizontal, AppSpacing.lg)
                    CategoryFilter(selection: $category)
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        section("Today", activities: activities.filter { Calendar.current.isDateInToday($0.startsAt) })
                        section("Tomorrow", activities: activities.filter { Calendar.current.isDateInTomorrow($0.startsAt) })
                        section("This week", activities: activities.filter {
                            !Calendar.current.isDateInToday($0.startsAt) &&
                            !Calendar.current.isDateInTomorrow($0.startsAt) &&
                            Calendar.current.isDate($0.startsAt, equalTo: .now, toGranularity: .weekOfYear)
                        })
                        let later = activities.filter {
                            !Calendar.current.isDateInToday($0.startsAt) &&
                            !Calendar.current.isDateInTomorrow($0.startsAt) &&
                            !Calendar.current.isDate($0.startsAt, equalTo: .now, toGranularity: .weekOfYear)
                        }
                        if !later.isEmpty { section("Coming up", activities: later) }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                }
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.md)
            }
            .background(AppColors.appBackground)
            .navigationTitle("Explore")
        }
    }

    private func section(_ title: String, activities: [Activity]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
            if activities.isEmpty {
                Text("No sample plans here yet.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.secondaryText)
            } else {
                ForEach(activities) { ActivityRow(activity: $0) }
            }
        }
    }
}

#Preview { ExploreView() }
