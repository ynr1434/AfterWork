import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.md) {
                Image(systemName: icon)
                    .font(AppTypography.title)
                    .foregroundStyle(.tint)
                    .padding(AppSpacing.md)
                    .background(
                        .tint.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                    )
                    .accessibilityHidden(true)

                Text(title)
                    .font(AppTypography.headline)

                if let subtitle {
                    Text(subtitle)
                        .font(AppTypography.body)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(AppSpacing.lg)
            .frame(maxHeight: .infinity)
        }
        .defaultScrollAnchor(.center)
    }
}

#Preview {
    EmptyStateView(
        icon: "rectangle.stack.fill",
        title: "Plans start here",
        subtitle: "Discover activities to enjoy with coworkers after work."
    )
}

#Preview("Title only") {
    EmptyStateView(icon: "bell.fill", title: "Stay in the loop")
}
