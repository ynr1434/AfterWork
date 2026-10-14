import SwiftUI

struct InlineMessage: View {
    let message: String
    var isError = true
    var retry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Label {
                Text(message).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: isError ? "exclamationmark.circle.fill" : "info.circle.fill")
            }
            .font(.subheadline)
            .foregroundStyle(isError ? AppColors.error : AppColors.secondaryText)
            if let retry {
                Button("Try Again", action: retry).buttonStyle(.bordered).frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.md)
        .background((isError ? AppColors.error : AppColors.accent).opacity(0.08), in: RoundedRectangle(cornerRadius: AppCornerRadius.medium))
        .accessibilityElement(children: .contain)
    }
}
