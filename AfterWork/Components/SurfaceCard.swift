import SwiftUI

/// A shared adaptive surface for cards and grouped content.
struct SurfaceCard: ViewModifier {
    var radius: CGFloat = AppCornerRadius.medium
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
             .background {
                RoundedRectangle(cornerRadius: radius).fill(AppColors.surface)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.035), radius: 12, x: 0, y: 4)
            }
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(AppColors.separator, lineWidth: 0.5))
    }
}

extension View {
    func surfaceCard(radius: CGFloat = AppCornerRadius.medium) -> some View {
        modifier(SurfaceCard(radius: radius))
    }
}
