import Foundation

@main
struct Stage4AuthChecks {
    static func main() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        func profile(_ name: String, interests: [String] = []) throws -> ProfileDTO {
            let values: [String: Any] = [
                "id": "10000000-0000-0000-0000-000000000001",
                "display_name": name, "interests": interests,
                "created_at": "2026-10-13T00:00:00Z", "updated_at": "2026-10-13T00:00:00Z"
            ]
            return try decoder.decode(ProfileDTO.self, from: JSONSerialization.data(withJSONObject: values))
        }
        let complete = try profile("Ada Lovelace", interests: ["board_games", "sports"])
        precondition(complete.isComplete && complete.initials == "AL")
        precondition(complete.interests == ["board_games", "sports"])
        precondition(AuthState.resolved(hasSession: false, profile: complete) == .signedOut)
        precondition(AuthState.resolved(hasSession: true, profile: nil) == .onboardingRequired)
        let incomplete = try profile(" \n ")
        precondition(AuthState.resolved(hasSession: true, profile: incomplete) == .onboardingRequired)
        precondition(AuthState.resolved(hasSession: true, profile: complete) == .signedIn)
        let tooLong = try profile(String(repeating: "a", count: 101))
        precondition(!tooLong.isComplete)
        var draft = ProfileDraft()
        precondition(draft.validationMessage != nil)
        draft.displayName = " \nAda \n"
        precondition(draft.validationMessage == nil && draft.trimmedName == "Ada")
        draft.displayName = String(repeating: "a", count: 100)
        precondition(draft.validationMessage == nil)
        draft.displayName += "a"
        precondition(draft.validationMessage != nil)
        let edit = ProfileDraft(profile: complete)
        precondition(edit.interests == Set(["board_games", "sports"]))
        precondition(ProfileDraft.optionalText("  ") == nil)
        precondition(ProfileDraft.optionalText(" Design ") == "Design")
        precondition(AuthCallback.accepts(URL(string: "com.kingz.AfterWork.AfterWork://auth/callback?code=test")!))
        for value in [
            "https://auth/callback?code=test", "com.kingz.AfterWork.AfterWork://other/callback",
            "com.kingz.AfterWork.AfterWork://auth/other", "com.kingz.AfterWork.AfterWork://auth/callback/",
            "com.kingz.AfterWork.AfterWork://user@auth/callback", "com.kingz.AfterWork.AfterWork://auth:42/callback",
            "com.kingz.AfterWork.AfterWork://auth/callback#access_token=test"
        ] { precondition(!AuthCallback.accepts(URL(string: value)!)) }
        print("Stage 4 routing, profile completeness, validation, DTO interests, and callback checks passed")
    }
}
