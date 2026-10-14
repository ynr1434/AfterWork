import SwiftUI

struct SecondaryButton: View {
    let title: String
    var symbol: String? = nil
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.sm) {
                if isLoading { ProgressView().tint(AppColors.accent) }
                if let symbol { Label(title, systemImage: symbol) }
                else { Text(title) }
            }
            .font(AppTypography.headline)
            .foregroundStyle(AppColors.primaryText)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, AppSpacing.xs)
        }
        .disabled(isLoading)
        .accessibilityValue(isLoading ? "In progress" : "")
        .buttonStyle(.bordered)
        .tint(AppColors.accent)
        .buttonBorderShape(.roundedRectangle(radius: AppCornerRadius.medium))
    }
}
