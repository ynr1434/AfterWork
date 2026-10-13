import SwiftUI

struct RootView: View {
    @State private var auth = AuthManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch auth.state {
            case .loading:
                VStack(spacing: AppSpacing.lg) {
                    if let error = auth.blockingError {
                        Image(systemName: "wifi.exclamationmark").font(.largeTitle)
                        Text(error).multilineTextAlignment(.center)
                        Button("Retry") { Task { await auth.retry() } }.buttonStyle(.borderedProminent)
                        if auth.user != nil {
                            Button("Sign Out", role: .destructive) { Task { await auth.signOut() } }
                                .disabled(auth.isBusy)
                        }
                        if let message = auth.message { Text(message).foregroundStyle(.red) }
                    } else {
                        ProgressView("Getting AfterWork ready…")
                    }
                    #if DEBUG
                    NavigationStack {
                        NavigationLink("Backend Connection") { BackendDebugView() }
                    }.frame(height: 80)
                    #endif
                }.padding(AppSpacing.lg)
            case .signedOut: AuthView()
            case .onboardingRequired: OnboardingView()
            case .signedIn: MainTabView()
            }
        }
        .environment(auth)
        .tint(AppColors.accent)
        .task { await auth.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await auth.refreshIfNeeded() } }
        }
        // OAuth is returned directly to the in-flight ASWebAuthenticationSession.
        // No general onOpenURL token handler is installed, preventing unsolicited callbacks.
    }
}
