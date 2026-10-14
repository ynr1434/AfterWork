import SwiftUI

// Asset colors adapt to appearance without importing UIKit.
enum AppColors {
    static let appBackground = Color("AppBackground")
    static let surface = Color("Surface")
    static let secondarySurface = Color("SecondarySurface")
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let accent = Color("AccentColor")
    static let buttonFill = Color(red: 0.08, green: 0.31, blue: 0.75)
    static let error = Color("ErrorColor")
    static let success = Color.green
    static let separator = Color.primary.opacity(0.12)
}
