import Foundation

nonisolated enum AuthState: Equatable {
    case loading, signedOut, onboardingRequired, signedIn

    static func resolved(hasSession: Bool, profile: ProfileDTO?) -> AuthState {
        guard hasSession else { return .signedOut }
        return profile?.isComplete == true ? .signedIn : .onboardingRequired
    }
}

nonisolated enum AuthCallback {
    // Matches the existing target's bundle identifier and URL Type.
    static let url = URL(string: "com.kingz.AfterWork.AfterWork://auth/callback")!

    static func accepts(_ url: URL) -> Bool {
        url.scheme?.lowercased() == self.url.scheme?.lowercased()
            && url.host == "auth" && URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath == "/callback"
            && url.user == nil && url.password == nil && url.port == nil
            && url.fragment == nil
    }
}

nonisolated struct ProfileDraft {
    var displayName = ""
    var department = ""
    var jobTitle = ""
    var interests: Set<String> = []

    init(profile: ProfileDTO? = nil, suggestedName: String = "") {
        displayName = profile?.displayName ?? suggestedName
        department = profile?.department ?? ""
        jobTitle = profile?.jobTitle ?? ""
        interests = Set(profile?.interests ?? [])
    }

    var trimmedName: String { displayName.trimmingCharacters(in: .whitespacesAndNewlines) }
    var validationMessage: String? {
        if trimmedName.isEmpty { return "Enter your display name." }
        if trimmedName.count > 100 { return "Use a display name of 100 characters or fewer." }
        return nil
    }
    static func optionalText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
