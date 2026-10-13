import AuthenticationServices
import UIKit

/// The SDK owns PKCE and exchanges the returned code. This helper owns only the browser
/// and validates the full callback destination before the SDK sees it.
@MainActor
final class OAuthBrowser: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, Error>?
    private var anchor: ASPresentationAnchor?

    func authenticate(url: URL) async throws -> URL {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .filter({ $0.activationState == .foregroundActive })
            .flatMap(\.windows).first(where: \.isKeyWindow) else {
            throw AppAuthError.browser
        }
        anchor = window
        defer { session = nil; anchor = nil }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let browser = ASWebAuthenticationSession(url: url, callbackURLScheme: AuthCallback.url.scheme) { [weak self] url, error in
                    Task { @MainActor in
                        guard let self else { return }
                        if let error { self.finish(.failure(error)) }
                        else if let url, AuthCallback.accepts(url) { self.finish(.success(url)) }
                        else { self.finish(.failure(AppAuthError.callback)) }
                    }
                }
                session = browser
                browser.presentationContextProvider = self
                if !browser.start() { finish(.failure(AppAuthError.browser)) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.session?.cancel()
                self?.finish(.failure(CancellationError()))
            }
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        let pending = continuation
        continuation = nil
        pending?.resume(with: result)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor ?? ASPresentationAnchor()
    }
}
