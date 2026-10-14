import SwiftUI

struct CategoryFilter: View {
    @Binding var selection: UUID?
    let categories: [CategoryDTO]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                Menu {
                    Button("All Categories") { selection = nil }
                    ForEach(categories) { category in
                        Button(category.name) { selection = category.id }
                    }
                } label: {
                    HStack(spacing: AppSpacing.sm) {
                        Text(selectedTitle)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Image(systemName: "chevron.down").font(.caption.weight(.bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .padding(.horizontal, AppSpacing.lg)
                    .background(AppColors.secondarySurface, in: RoundedRectangle(cornerRadius: AppCornerRadius.medium))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                }
                .accessibilityLabel("Activity category")
                .accessibilityValue(selectedTitle)
                .padding(.horizontal, AppSpacing.lg)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.sm) {
                        Button { selection = nil } label: {
                            Text("All Categories")
                                .font(AppTypography.caption.weight(.semibold))
                                .padding(.horizontal, AppSpacing.md)
                                .padding(.vertical, AppSpacing.sm)
                                .background(selection == nil ? AppColors.accent.opacity(0.18) : AppColors.secondarySurface, in: Capsule())
                                .overlay {
                                    if selection == nil { Capsule().strokeBorder(AppColors.accent, lineWidth: 2) }
                                }
                                .frame(minHeight: 44)
                        }.accessibilityAddTraits(selection == nil ? .isSelected : [])
                        ForEach(categories) { category in
                            Button { selection = category.id } label: {
                                CategoryChip(category: ActivityCategory(databaseSlug: category.slug),
                                             isSelected: selection == category.id, title: category.name)
                                    .frame(minHeight: 44)
                            }.accessibilityAddTraits(selection == category.id ? .isSelected : [])
                        }
                    }.padding(.horizontal, AppSpacing.lg)
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppColors.primaryText)
        .accessibilityLabel("Activity categories")
    }

    private var selectedTitle: String {
        guard let selection, let category = categories.first(where: { $0.id == selection }) else {
            return "All Categories"
        }
        return category.name
    }
}
