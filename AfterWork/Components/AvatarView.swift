import SwiftUI

struct AvatarView: View {
    let initials: String
    var size: CGFloat = 40
    var color: Color = AppColors.accent

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.32, weight: .bold, design: .rounded))
            .foregroundStyle(AppColors.primaryText)
            .frame(width: size, height: size)
            .background(color.opacity(0.18), in: Circle())
            .overlay(Circle().strokeBorder(AppColors.surface, lineWidth: 2))
            .accessibilityLabel("Avatar, \(initials)")
    }
}

struct AvatarGroup: View {
    let initials: [String]
    let totalCount: Int

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            HStack(spacing: -10) {
                ForEach(Array(initials.prefix(3).enumerated()), id: \.offset) { index, initials in
                    AvatarView(initials: initials, size: 34, color: index.isMultiple(of: 2) ? .blue : .purple)
                }
            }
            if totalCount > min(initials.count, 3) {
                Text("+\(totalCount - min(initials.count, 3))")
                    .font(AppTypography.caption.weight(.semibold))
                    .foregroundStyle(AppColors.secondaryText)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(totalCount) participants")
    }
}

#Preview {
    AvatarGroup(initials: MockActivities.preview.participantInitials, totalCount: MockActivities.preview.participantCount)
}
