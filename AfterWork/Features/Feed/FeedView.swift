import SwiftUI

struct FeedView: View {
    @State private var category: ActivityCategory?
    @State private var index = 0
    @State private var feedback: String?

    private var activities: [Activity] {
        MockActivities.activities.filter { category == nil || $0.category == category }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    Text("What's happening after work?")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.secondaryText)
                        .padding(.horizontal, AppSpacing.lg)

                    CategoryFilter(selection: $category)

                    if activities.isEmpty {
                        VStack(spacing: AppSpacing.md) {
                            Text("More plans are on the way")
                                .font(AppTypography.headline)
                            Text("There are no sample activities in this category yet.")
                                .foregroundStyle(AppColors.secondaryText)
                            SecondaryButton(title: "Show all activities") { category = nil }
                        }
                        .padding(AppSpacing.lg)
                    } else {
                        let activity = activities[min(index, activities.count - 1)]
                        VStack(spacing: AppSpacing.lg) {
                            ActivityCard(activity: activity)
                            HStack(alignment: .top, spacing: AppSpacing.lg) {
                                action("Skip", symbol: "xmark", color: .secondary) {
                                    index = (index + 1) % activities.count
                                }
                                action("Save", symbol: "bookmark", color: AppColors.accent) {
                                    feedback = "Saving activities is coming soon. This is a visual preview."
                                }
                                action("Going", symbol: "checkmark", color: .green) {
                                    feedback = "Joining activities is coming soon. This is a visual preview."
                                }
                            }
                            Text("Sample activities · \(min(index + 1, activities.count)) of \(activities.count)")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.secondaryText)
                        }
                        .padding(.horizontal, AppSpacing.lg)
                    }
                }
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.md)
            }
            .background(AppColors.appBackground)
            .navigationTitle("AfterWork")
            .onChange(of: category) { index = 0 }
            .alert("Stage 2 preview", isPresented: Binding(
                get: { feedback != nil },
                set: { if !$0 { feedback = nil } }
            )) {
                Button("Got it", role: .cancel) { feedback = nil }
            } message: {
                Text(feedback ?? "")
            }
        }
    }

    private func action(_ title: String, symbol: String, color: Color, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: AppSpacing.sm) {
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppColors.primaryText)
                    .frame(width: 60, height: 60)
                    .background(color.opacity(0.15), in: Circle())
                Text(title)
                    .font(AppTypography.caption.weight(.semibold))
                    .foregroundStyle(AppColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title == "Skip" ? "Skip to next sample activity" : "\(title), preview")
    }
}

#Preview { FeedView() }
#Preview("Dark") { FeedView().preferredColorScheme(.dark) }
