import SwiftUI

struct ProfileView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    VStack(spacing: AppSpacing.sm) {
                        AvatarView(initials: "YN", size: 88)
                            .accessibilityHidden(true)
                        Text("Yernar").font(AppTypography.title)
                        Text("Product Designer").font(AppTypography.headline)
                        Text("Digital Products")
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(AppSpacing.lg)

                    VStack(spacing: AppSpacing.md) {
                        statistic("Upcoming", symbol: "calendar", count: 3)
                        statistic("Created", symbol: "plus.circle", count: 2)
                        statistic("Joined", symbol: "person.2", count: 8)
                        statistic("Saved", symbol: "bookmark", count: 4)
                    }
                    Text("Sample profile · Just a preview for now")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.secondaryText)
                }
                .padding(AppSpacing.lg)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .background(AppColors.appBackground)
            .navigationTitle("Profile")
        }
    }

    private func statistic(_ title: String, symbol: String, count: Int) -> some View {
        HStack(spacing: AppSpacing.md) {
            Label(title, systemImage: symbol)
            Spacer(minLength: AppSpacing.sm)
            Text(count, format: .number).font(.title2.bold())
        }
        .font(AppTypography.headline)
        .padding(AppSpacing.lg)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: AppCornerRadius.medium))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(count)")
    }
}

#Preview { ProfileView() }
