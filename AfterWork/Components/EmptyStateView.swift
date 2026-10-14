import SwiftUI

/// Inline content can live inside an existing ScrollView without nesting scroll views.
struct EmptyStateContent: View {
    let icon: String
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.title.weight(.medium))
                .foregroundStyle(AppColors.accent)
                .padding(AppSpacing.lg)
                .background(AppColors.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: AppCornerRadius.large))
                .accessibilityHidden(true)
            Text(title).font(.title3.bold()).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.lg)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    var subtitle: String?

    var body: some View {
        ScrollView {
            EmptyStateContent(icon: icon, title: title, subtitle: subtitle)
        }
        .defaultScrollAnchor(.center)
        .background(AppColors.appBackground)
    }
}
