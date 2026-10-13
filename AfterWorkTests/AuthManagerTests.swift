import XCTest
import Supabase
@testable import AfterWork

@MainActor
final class AuthManagerTests: XCTestCase {
    private func session(id: UUID = UUID()) -> Session {
        Session(accessToken: "test-only", tokenType: "bearer", expiresIn: 3600,
                expiresAt: Date().timeIntervalSince1970 + 3600, refreshToken: "test-only",
                user: User(id: id, appMetadata: [:], userMetadata: [:], aud: "authenticated",
                           createdAt: Date(), updatedAt: Date()))
    }

    private func profile(id: UUID, name: String = "Ada") -> ProfileDTO {
        ProfileDTO(id: id, email: nil, displayName: name, avatarUrl: nil, department: nil,
                   jobTitle: nil, interests: ["sports"], createdAt: Date(), updatedAt: Date())
    }

    private func settle(_ manager: AuthManager) async {
        for _ in 0..<100 {
            if manager.state != .loading || manager.blockingError != nil { return }
            await Task.yield()
        }
        XCTFail("Profile resolution did not settle")
    }

    func testMissingSessionRoutesToAuth() async {
        let manager = AuthManager(restoreSession: { throw Supabase.AuthError.sessionMissing },
                                  loadProfile: { _ in XCTFail("Must not fetch without a session"); return nil })
        await manager.restore()
        XCTAssertEqual(manager.state, .signedOut)
        XCTAssertNil(manager.user)
    }

    func testExistingProfileRoutesToTabs() async {
        let session = session()
        let profile = profile(id: session.user.id)
        let manager = AuthManager(restoreSession: { session }, loadProfile: { id in
            XCTAssertEqual(id, session.user.id)
            return profile
        })
        await manager.restore()
        await settle(manager)
        XCTAssertEqual(manager.state, .signedIn)
        XCTAssertEqual(manager.profile?.id, session.user.id)
    }

    func testMissingAndIncompleteProfilesRequireOnboarding() async {
        let session = session()
        for result in [nil, profile(id: session.user.id, name: " \n ")] {
            let manager = AuthManager(restoreSession: { session }, loadProfile: { _ in result })
            await manager.restore()
            await settle(manager)
            XCTAssertEqual(manager.state, .onboardingRequired)
        }
    }

    func testNetworkFailureDoesNotEnterOnboardingAndRetryWorks() async {
        let session = session()
        let profile = profile(id: session.user.id)
        var fail = true
        let manager = AuthManager(restoreSession: { session }, loadProfile: { _ in
            if fail { throw URLError(.notConnectedToInternet) }
            return profile
        })
        await manager.restore()
        await settle(manager)
        XCTAssertEqual(manager.state, .loading)
        XCTAssertNotNil(manager.blockingError)
        XCTAssertNil(manager.profile)
        fail = false
        await manager.restore()
        await settle(manager)
        XCTAssertEqual(manager.state, .signedIn)
        XCTAssertNil(manager.blockingError)
    }

    func testRestoreTransportFailureLocksNavigation() async {
        let manager = AuthManager(restoreSession: { throw URLError(.timedOut) }, loadProfile: { _ in nil })
        await manager.restore()
        XCTAssertEqual(manager.state, .loading)
        XCTAssertNotNil(manager.blockingError)
    }

    func testLateProfileResponseCannotUndoSignOut() async {
        let session = session()
        let profile = profile(id: session.user.id)
        var signedOut = false
        var pending: CheckedContinuation<ProfileDTO?, Error>?
        let manager = AuthManager(restoreSession: {
            if signedOut { throw Supabase.AuthError.sessionMissing }
            return session
        }, loadProfile: { _ in
            try await withCheckedThrowingContinuation { pending = $0 }
        })
        await manager.restore()
        while pending == nil { await Task.yield() }
        signedOut = true
        await manager.restore()
        pending?.resume(returning: profile)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(manager.state, .signedOut)
        XCTAssertNil(manager.profile)
        XCTAssertNil(manager.session)
    }
}
