import SwiftUI

struct CategoryChip: View {
    let category: ActivityCategory
    var isSelected = false
    var title: String? = nil

    var body: some View {
        Label(title ?? category.displayName, systemImage: category.symbol)
            .font(AppTypography.caption.weight(.semibold))
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .foregroundStyle(AppColors.primaryText)
            .background(isSelected ? AppColors.accent.opacity(0.18) : AppColors.secondarySurface, in: Capsule())
            .overlay {
                if isSelected {
                    Capsule().strokeBorder(AppColors.accent, lineWidth: 2)
                }
            }
    }
}

#Preview {
    HStack {
        CategoryChip(category: .sports, isSelected: true)
        CategoryChip(category: .boardGames)
    }
}
