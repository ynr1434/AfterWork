import SwiftUI

struct CategoryFilter: View {
    @Binding var selection: ActivityCategory?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                Button { selection = nil } label: {
                    Text("All")
                        .font(AppTypography.caption.weight(.semibold))
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                        .background(selection == nil ? AppColors.accent.opacity(0.18) : AppColors.secondarySurface, in: Capsule())
                        .overlay {
                            if selection == nil {
                                Capsule().strokeBorder(AppColors.accent, lineWidth: 2)
                            }
                        }
                        .frame(minHeight: 44)
                }
                .accessibilityAddTraits(selection == nil ? .isSelected : [])

                ForEach(ActivityCategory.allCases) { category in
                    Button { selection = category } label: {
                        CategoryChip(category: category, isSelected: selection == category)
                            .frame(minHeight: 44)
                    }
                    .accessibilityAddTraits(selection == category ? .isSelected : [])
                }
            }
            .padding(.horizontal, AppSpacing.lg)
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppColors.primaryText)
        .accessibilityLabel("Activity categories")
    }
}
