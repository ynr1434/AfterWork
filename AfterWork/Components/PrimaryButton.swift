import SwiftUI

struct PrimaryButton: View {
    let title: String
    var symbol: String? = nil
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.sm) {
                if isLoading { ProgressView().tint(.white) }
                if let symbol { Label(title, systemImage: symbol) }
                else { Text(title) }
            }
            .font(AppTypography.headline)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, AppSpacing.xs)
        }
        .disabled(isLoading)
        .accessibilityValue(isLoading ? "In progress" : "")
        .buttonStyle(.borderedProminent)
        .tint(AppColors.buttonFill)
        .foregroundStyle(.white)
        .buttonBorderShape(.roundedRectangle(radius: AppCornerRadius.medium))
    }
}

#Preview {
    PrimaryButton(title: "Create activity", symbol: "plus") {}
        .padding()
}
