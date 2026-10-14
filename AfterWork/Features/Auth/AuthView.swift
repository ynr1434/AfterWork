import AuthenticationServices
import SwiftUI

struct AuthView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 52, weight: .medium)).foregroundStyle(AppColors.accent)
                        .frame(width: 112, height: 112)
                        .background(AppColors.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 32))
                        .accessibilityHidden(true)
                    VStack(spacing: AppSpacing.md) {
                        Text("AfterWork").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                        Text("Work ends. Life doesn't.")
                            .font(.title3).foregroundStyle(AppColors.secondaryText)
                        Text("Find your people. Make plans. Enjoy what comes next.")
                            .multilineTextAlignment(.center).foregroundStyle(AppColors.secondaryText)
                    }
                    VStack(spacing: AppSpacing.md) {
                        SignInWithAppleButton(.continue) { request in
                            auth.prepareApple(request)
                        } onCompletion: { result in
                            Task { await auth.completeApple(result) }
                        }
                        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                        .id(colorScheme)
                        .frame(height: typeSize.isAccessibilitySize ? 64 : 54)
                        .accessibilityLabel("Continue with Apple")
                        Button { Task { await auth.signInWithGoogle() } } label: {
                            HStack(spacing: 12) {
                                Image("GoogleG").resizable().scaledToFit().frame(width: 20, height: 20)
                                    .accessibilityHidden(true)
                                Text("Continue with Google").font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, AppSpacing.md).padding(.vertical, AppSpacing.sm)
                            .frame(maxWidth: .infinity, minHeight: typeSize.isAccessibilitySize ? 64 : 54)
                            .foregroundStyle(Color.primary)
                            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppColors.separator))
                        }.accessibilityLabel("Continue with Google")
                    }.disabled(auth.isBusy)
                    ProgressView("Signing in…").opacity(auth.isBusy ? 1 : 0).accessibilityHidden(!auth.isBusy)
                    if let message = auth.message {
                        InlineMessage(message: message)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                    #if DEBUG
                    NavigationLink("Backend Connection") { BackendDebugView() }
                        .font(AppTypography.caption)
                    #endif
                }
                .padding(AppSpacing.xl)
                .padding(.top, AppSpacing.lg)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }.background(AppColors.appBackground)
        }
    }
}
