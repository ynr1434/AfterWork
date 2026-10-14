import AuthenticationServices
import CryptoKit
import Observation
import Security
import Supabase

@MainActor @Observable
final class AuthManager {
    private(set) var state: AuthState = .loading
    private(set) var session: Session?
    private(set) var profile: ProfileDTO?
    private(set) var isBusy = false
    private(set) var suggestedName = ""
    var message: String?
    private(set) var blockingError: String?

    @ObservationIgnored var prepareForSignOut: (() async throws -> Void)?
    @ObservationIgnored var onSessionEnded: (() -> Void)?

    var userID: UUID? { session?.user.id }
    var email: String? { session?.user.email }
    var metadataName: String { user?.userMetadata["full_name"]?.stringValue ?? "" }
    var user: User? { session?.user }
    @ObservationIgnored private var listener: Task<Void, Never>?
    @ObservationIgnored private var profileTask: Task<Void, Never>?
    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private var appleNonce: String?
    @ObservationIgnored private let browser = OAuthBrowser()
    @ObservationIgnored private let restoreSession: () async throws -> Session
    @ObservationIgnored private let loadProfile: (UUID) async throws -> ProfileDTO?

    init(
        restoreSession: @escaping () async throws -> Session = {
            try await SupabaseManager.shared.client.auth.session
        },
        loadProfile: @escaping (UUID) async throws -> ProfileDTO? = { id in
            try await ProfileRepository(client: SupabaseManager.shared.client).fetchProfile(id: id)
        }
    ) {
        self.restoreSession = restoreSession
        self.loadProfile = loadProfile
    }

    func start() async {
        guard listener == nil else { return }
        do {
            let client = try SupabaseManager.shared.client
            listener = Task { [weak self] in
                for await (event, session) in client.auth.authStateChanges {
                    guard !Task.isCancelled, let self else { return }
                    // Explicit restoration below validates/refreshes persisted sessions.
                    switch event {
                    case .signedOut: self.clearSession()
                    case .signedIn: if let session { self.accept(session) }
                    case .tokenRefreshed, .userUpdated:
                        if let session {
                            if self.session?.user.id == session.user.id { self.session = session }
                            else { self.accept(session) }
                        }
                    default: break
                    }
                }
            }
            await restore()
        } catch {
            blockingError = (error as? DatabaseError)?.errorDescription ?? "We couldn't start sign-in. Please retry."
        }
    }

    func retry() async {
        if listener == nil { await start() } else { await restore() }
    }

    func restore() async {
        let request = UUID()
        revision = request
        profileTask?.cancel()
        state = .loading
        blockingError = nil
        do {
            let restored = try await restoreSession()
            guard request == revision else { return }
            accept(restored)
        } catch {
            guard request == revision else { return }
            if let authError = error as? Supabase.AuthError, authError == .sessionMissing {
                clearSession()
            } else {
                // Refresh transport errors preserve the stored session for a later retry.
                blockingError = (error as? DatabaseError)?.errorDescription
                    ?? "We couldn't restore your session. Check your connection and retry."
            }
        }
    }

    func refreshIfNeeded() async {
        guard session != nil, !isBusy else { return }
        do {
            let refreshed = try await SupabaseManager.shared.client.auth.session
            if refreshed.user.id == session?.user.id { session = refreshed }
        } catch {
            // Lock authenticated navigation until restoration succeeds or the SDK signs out.
            await restore()
        }
    }

    private func accept(_ newSession: Session) {
        let request = UUID()
        revision = request
        profileTask?.cancel()
        if session?.user.id != newSession.user.id { profile = nil }
        session = newSession
        state = .loading
        blockingError = nil
        let loadProfile = self.loadProfile
        profileTask = Task { [weak self] in
            do {
                let result = try await loadProfile(newSession.user.id)
                guard let self, !Task.isCancelled, self.revision == request else { return }
                self.profile = result
                self.state = .resolved(hasSession: true, profile: result)
            } catch {
                guard let self, !Task.isCancelled, self.revision == request else { return }
                self.blockingError = "We couldn't load your profile. Check your connection and retry."
            }
        }
    }

    func prepareApple(_ request: ASAuthorizationAppleIDRequest) {
        guard !isBusy else { return }
        message = nil
        do {
            _ = try SupabaseManager.shared.client
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                throw AppAuthError.nonce
            }
            let nonce = bytes.map { String(format: "%02x", $0) }.joined()
            appleNonce = nonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
            isBusy = true
        } catch { message = safeMessage(error); appleNonce = nil }
    }

    func completeApple(_ result: Result<ASAuthorization, Error>) async {
        defer { appleNonce = nil; isBusy = false }
        do {
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8),
                  let nonce = appleNonce else { throw AppAuthError.appleCredential }
            if let name = credential.fullName {
                suggestedName = PersonNameComponentsFormatter().string(from: name)
            }
            let client = try SupabaseManager.shared.client
            let session = try await client.auth.signInWithIdToken(credentials: .init(
                provider: .apple, idToken: token, nonce: nonce
            ))
            // Apple supplies name only on first authorization. Persist as a suggestion,
            // never as an authorization claim; onboarding still requires explicit saving.
            if !suggestedName.isEmpty {
                do {
                    _ = try await client.auth.update(user: .init(data: ["full_name": .string(suggestedName)]))
                } catch {
                    message = "You're signed in. Please confirm your name below; we couldn't save Apple's name suggestion."
                }
            }
            accept(session)
        } catch { if !isCancellation(error) { message = safeMessage(error) } }
    }

    func signInWithGoogle() async {
        guard !isBusy else { return }
        isBusy = true
        message = nil
        suggestedName = ""
        defer { isBusy = false }
        do {
            let session = try await SupabaseManager.shared.client.auth.signInWithOAuth(
                provider: .google, redirectTo: AuthCallback.url,
                launchFlow: { [browser] url in try await browser.authenticate(url: url) }
            )
            accept(session)
        } catch { if !isCancellation(error) { message = safeMessage(error) } }
    }

    func saveProfile(_ draft: ProfileDraft) async -> Bool {
        guard !isBusy, let id = user?.id else { return false }
        isBusy = true
        message = nil
        // Invalidate older profile fetches so they cannot overwrite a successful save.
        revision = UUID()
        profileTask?.cancel()
        defer { isBusy = false }
        do {
            let saved = try await ProfileRepository(client: SupabaseManager.shared.client).save(draft)
            guard user?.id == id, saved.id == id else { return false }
            profile = saved
            state = .resolved(hasSession: true, profile: saved)
            return true
        } catch {
            guard user?.id == id else { return false }
            message = "We couldn't save your profile. Check your connection and try again."
            return false
        }
    }

    func signOut() async {
        guard !isBusy else { return }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do { try await prepareForSignOut?() }
        catch { message = "We couldn't remove this device's push registration. Check your connection and retry signing out."; return }
        do {
            try await SupabaseManager.shared.client.auth.signOut(scope: .local)
            clearSession()
        } catch {
            // SDK removes local credentials before attempting server revocation.
            if (try? SupabaseManager.shared.client.auth.currentSession) == nil {
                clearSession()
                message = "You're signed out on this device. We couldn't reach the server to revoke the session."
            } else {
                message = "We couldn't sign you out. Please try again."
            }
        }
    }

    private func clearSession() {
        if session != nil { onSessionEnded?() }
        revision = UUID()
        profileTask?.cancel()
        session = nil
        profile = nil
        suggestedName = ""
        appleNonce = nil
        blockingError = nil
        state = .signedOut
    }

    private func isCancellation(_ error: Error) -> Bool {
        error is CancellationError
            || (error as? ASAuthorizationError)?.code == .canceled
            || (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
    }

    private func safeMessage(_ error: Error) -> String {
        if let error = error as? DatabaseError { return error.errorDescription ?? "Check backend configuration." }
        if let error = error as? AppAuthError { return error.errorDescription ?? "Please try again." }
        return "We couldn't sign you in. Check your connection and try again."
    }
}
