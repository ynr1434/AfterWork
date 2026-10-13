import AuthenticationServices
import SwiftUI

struct AuthView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 64)).foregroundStyle(AppColors.accent)
                        .accessibilityHidden(true)
                    VStack(spacing: AppSpacing.md) {
                        Text("AfterWork").font(.largeTitle.bold())
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
                        .frame(height: 50)
                        .accessibilityLabel("Continue with Apple")
                        Button { Task { await auth.signInWithGoogle() } } label: {
                            HStack(spacing: 12) {
                                Image("GoogleG").resizable().scaledToFit().frame(width: 20, height: 20)
                                    .accessibilityHidden(true)
                                Text("Continue with Google").font(.system(size: 17, weight: .medium))
                            }
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .foregroundStyle(Color.primary)
                            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppColors.separator))
                        }.accessibilityLabel("Continue with Google")
                    }.disabled(auth.isBusy)
                    if auth.isBusy { ProgressView("Signing in…") }
                    if let message = auth.message {
                        Text(message).foregroundStyle(.red).multilineTextAlignment(.center)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                    #if DEBUG
                    NavigationLink("Backend Connection") { BackendDebugView() }
                        .font(AppTypography.caption)
                    #endif
                }
                .padding(AppSpacing.xl)
                .padding(.top, 64)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }.background(AppColors.appBackground)
        }
    }
}
