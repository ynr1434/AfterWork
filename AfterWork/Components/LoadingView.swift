import SwiftUI

struct LoadingView: View {
    var title = "Loading…"

    var body: some View {
        ProgressView(title)
            .tint(AppColors.accent)
            .padding(AppSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
