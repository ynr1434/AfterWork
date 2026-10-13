import SwiftUI

struct ActivityCover: View {
    let activity: Activity
    var compact = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let imageName = activity.imageName {
                    Image(imageName)
                        .resizable()
                        .scaledToFill()
                } else {
                    AppColors.secondarySurface
                    LinearGradient(
                        colors: [activity.category.coverColor.opacity(0.42), activity.category.coverColor.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Circle()
                        .stroke(activity.category.coverColor.opacity(0.25), lineWidth: compact ? 12 : 28)
                        .frame(width: geometry.size.width * 0.7)
                        .offset(x: geometry.size.width * 0.36, y: -geometry.size.height * 0.25)
                    Image(systemName: activity.category.symbol)
                        .font(.system(size: compact ? 28 : 86, weight: .medium))
                        .foregroundStyle(AppColors.primaryText.opacity(0.8))
                        .rotationEffect(.degrees(-10))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
    }
}
