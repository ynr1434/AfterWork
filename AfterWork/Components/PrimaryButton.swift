import SwiftUI

struct PrimaryButton: View {
    let title: String
    var symbol: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let symbol { Label(title, systemImage: symbol) }
                else { Text(title) }
            }
            .font(AppTypography.headline)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, AppSpacing.xs)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppColors.accent)
        .buttonBorderShape(.roundedRectangle(radius: AppCornerRadius.medium))
    }
}

#Preview {
    PrimaryButton(title: "Create activity", symbol: "plus") {}
        .padding()
}
