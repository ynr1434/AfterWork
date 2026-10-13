import SwiftUI

struct ActivityRow: View {
    let activity: Activity
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    cover
                    details
                }
            } else {
                HStack(alignment: .top, spacing: AppSpacing.md) {
                    cover
                    details
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: AppCornerRadius.medium))
        .accessibilityElement(children: .combine)
    }

    private var cover: some View {
        ActivityCover(activity: activity, compact: true)
            .frame(width: 76, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.small))
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(activity.category.displayName)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.secondaryText)
            Text(activity.title).font(AppTypography.headline)
            Text(activity.scheduleText).font(AppTypography.caption)
            Text(activity.locationName).font(AppTypography.caption)
            Text(activity.participationText).font(AppTypography.caption.weight(.semibold))
        }
        .foregroundStyle(AppColors.primaryText)
    }
}
