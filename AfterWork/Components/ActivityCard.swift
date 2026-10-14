import SwiftUI

struct ActivityCard: View {
    let activity: Activity
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ActivityCover(activity: activity)
                .frame(height: 190)

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                CategoryChip(category: activity.category, title: activity.categoryDisplayName)
                Text(activity.title)
                    .font(AppTypography.title)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Label(activity.scheduleText, systemImage: "calendar")
                    Label(activity.locationName, systemImage: "mappin.and.ellipse")
                }
                .font(.subheadline)
                .foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

                if !activity.description.isEmpty {
                    Text(activity.description)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Rectangle().fill(AppColors.separator).frame(height: 1)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: AppSpacing.md) {
                        avatars
                        Spacer(minLength: 0)
                        participants
                    }
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        avatars
                        participants
                    }
                }
            }
            .padding(AppSpacing.lg)
        }
        .foregroundStyle(AppColors.primaryText)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large))
        .surfaceCard(radius: AppCornerRadius.large)
    }

    private var avatars: some View {
        Group {
            if activity.participantInitials.isEmpty {
                AvatarView(initials: activity.organizerInitials)
            } else {
                AvatarGroup(initials: activity.participantInitials, totalCount: activity.participantCount)
            }
        }
            .accessibilityHidden(true)
    }

    private var participants: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(activity.participationText).font(AppTypography.headline)
            Text("Hosted by \(activity.organizerName)")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.secondaryText)
        }
    }
}

#Preview("Light") {
    ScrollView { ActivityCard(activity: MockActivities.preview).padding() }
        .background(AppColors.appBackground)
}

#Preview("Dark · Large text") {
    ScrollView { ActivityCard(activity: MockActivities.preview).padding() }
        .background(AppColors.appBackground)
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility3)
}
