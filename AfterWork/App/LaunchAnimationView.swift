import SwiftUI

struct LaunchAnimationView: View {
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var afterIsVisible = false
    @State private var workIsVisible = false
    @State private var glassesAreVisible = false
    @State private var glassOffset: CGFloat = 260
    @State private var glassRotation = 36.0
    @State private var sparkleOpacity = 0.0
    @State private var sparkleScale: CGFloat = 0.3
    @State private var sparkleOffset: CGFloat = -20

    private let navy = Color(red: 7 / 255, green: 23 / 255, blue: 40 / 255)
    private let orange = Color(red: 1, green: 117 / 255, blue: 27 / 255)
    private let glassGold = Color(red: 1, green: 192 / 255, blue: 107 / 255)
    private let drinkOrange = Color(red: 1, green: 134 / 255, blue: 30 / 255)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 250 / 255, green: 247 / 255, blue: 241 / 255)

                ZStack {
                    HStack(spacing: -5) {
                        Text("After")
                            .foregroundStyle(navy)
                            .opacity(afterIsVisible ? 1 : 0)
                            .offset(y: afterIsVisible ? 0 : 22)
                        Text("Work")
                            .foregroundStyle(orange)
                            .opacity(workIsVisible ? 1 : 0)
                            .offset(x: workIsVisible ? 0 : 35)
                    }
                    .font(.system(size: logoSize(for: geometry.size.width), weight: .heavy, design: .rounded))
                    .tracking(-3.2)
                    .offset(y: 48)

                    HStack(spacing: 14) {
                        wineGlass
                            .rotationEffect(.degrees(glassRotation))
                            .offset(x: -glassOffset)
                        wineGlass
                            .rotationEffect(.degrees(-glassRotation))
                            .offset(x: glassOffset)
                    }
                    .opacity(glassesAreVisible ? 1 : 0)
                    .offset(y: -92)

                    Text("✦")
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(Color(red: 1, green: 173 / 255, blue: 54 / 255))
                        .opacity(sparkleOpacity)
                        .scaleEffect(sparkleScale)
                        .offset(y: sparkleOffset - 92)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(width: min(geometry.size.width * 0.92, 900), height: min(450, geometry.size.height * 0.78))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .ignoresSafeArea()
            .task { await playAnimation() }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AfterWork")
        .accessibilityAddTraits(.isImage)
    }

    private var wineGlass: some View {
        ZStack {
            WineGlassBowl()
                .fill(glassGold)
            WineGlassLiquid()
                .fill(drinkOrange)
            WineGlassBowl()
                .stroke(navy, style: StrokeStyle(lineWidth: 3.5, lineJoin: .round))
            WineGlassStem()
                .stroke(navy, style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }
        .frame(width: 68, height: 102)
        .drawingGroup()
        .accessibilityHidden(true)
    }

    private func logoSize(for width: CGFloat) -> CGFloat {
        min(max(width * 0.14, 48), 88)
    }

    @MainActor
    private func playAnimation() async {
        if reduceMotion {
            afterIsVisible = true
            workIsVisible = true
            glassesAreVisible = true
            glassOffset = 9
            glassRotation = 7
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard !Task.isCancelled else { return }
            onFinished()
            return
        }

        try? await Task.sleep(nanoseconds: 250_000_000)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.78)) { afterIsVisible = true }

        try? await Task.sleep(nanoseconds: 830_000_000)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 1.08)) { workIsVisible = true }

        try? await Task.sleep(nanoseconds: 1_080_000_000)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 1.08)) {
            glassesAreVisible = true
            glassOffset = 0
            glassRotation = 16
        }

        try? await Task.sleep(nanoseconds: 900_000_000)
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) {
            sparkleOpacity = 1
            sparkleScale = 1.4
            sparkleOffset = -20
        }

        try? await Task.sleep(nanoseconds: 360_000_000)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.27)) {
            glassOffset = 9
            glassRotation = 7
        }

        try? await Task.sleep(nanoseconds: 380_000_000)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.7)) {
            sparkleOpacity = 0
            sparkleScale = 0.6
            sparkleOffset = -40
        }

        try? await Task.sleep(nanoseconds: 700_000_000)
        guard !Task.isCancelled else { return }
        onFinished()
    }
}

private struct WineGlassBowl: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var path = Path()
        path.move(to: point(0.25, 0.07))
        path.addLine(to: point(0.75, 0.07))
        path.addLine(to: point(0.69, 0.37))
        path.addQuadCurve(to: point(0.5, 0.51), control: point(0.64, 0.51))
        path.addQuadCurve(to: point(0.31, 0.37), control: point(0.36, 0.51))
        path.closeSubpath()
        return path
    }
}

private struct WineGlassLiquid: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var path = Path()
        path.move(to: point(0.31, 0.275))
        path.addLine(to: point(0.69, 0.275))
        path.addLine(to: point(0.66, 0.38))
        path.addQuadCurve(to: point(0.5, 0.47), control: point(0.62, 0.47))
        path.addQuadCurve(to: point(0.34, 0.38), control: point(0.38, 0.47))
        path.closeSubpath()
        return path
    }
}

private struct WineGlassStem: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var path = Path()
        path.move(to: point(0.5, 0.51))
        path.addLine(to: point(0.5, 0.84))
        path.move(to: point(0.29, 0.87))
        path.addLine(to: point(0.71, 0.87))
        return path
    }
}
