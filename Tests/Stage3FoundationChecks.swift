// Standalone checks; run with the command in README. No network or real credentials.
import Foundation

@main
struct Stage3FoundationChecks {
    @MainActor
    static func main() throws {
        func expectConfigurationError(_ values: [String: Any]) {
            do {
                _ = try SupabaseConfiguration.load(values: values)
                fatalError("Invalid configuration was accepted")
            } catch is DatabaseError {
                // Expected, with no credential values exposed in the error.
            } catch { fatalError("Unexpected error type") }
        }
        expectConfigurationError([:])
        expectConfigurationError(["SUPABASE_URL": "", "SUPABASE_ANON_KEY": ""])
        expectConfigurationError(["SUPABASE_URL": "$(SUPABASE_URL)", "SUPABASE_ANON_KEY": "$(SUPABASE_ANON_KEY)"])
        let testURL = "https://example.invalid"
        let testPublicKey = "sb_publishable_test_fixture_only"
        expectConfigurationError(["SUPABASE_URL": "http://example.invalid", "SUPABASE_ANON_KEY": testPublicKey])
        expectConfigurationError(["SUPABASE_URL": testURL, "SUPABASE_ANON_KEY": "sb_secret_test_fixture_only"])
        expectConfigurationError(["SUPABASE_URL": testURL, "SUPABASE_ANON_KEY": "malformed"])
        func testJWT(role: String) -> String {
            let payload = Data("{\"role\":\"\(role)\"}".utf8).base64EncodedString()
                .replacingOccurrences(of: "=", with: "")
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
            return "test.\(payload).not-a-real-signature"
        }
        expectConfigurationError(["SUPABASE_URL": testURL, "SUPABASE_ANON_KEY": testJWT(role: "service_role")])
        _ = try SupabaseConfiguration.load(values: ["SUPABASE_URL": testURL, "SUPABASE_ANON_KEY": testPublicKey])
        _ = try SupabaseConfiguration.load(values: ["SUPABASE_URL": testURL, "SUPABASE_ANON_KEY": testJWT(role: "anon")])

        let id = "10000000-0000-0000-0000-000000000001"
        let date = "2026-10-13T14:00:00Z"
        let base: [String: Any] = ["id": id, "created_at": date, "updated_at": date]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        func row<T: Codable>(_ type: T.Type, _ fields: [String: Any]) throws -> T {
            let json = base.merging(fields) { _, new in new }
            let value = try decoder.decode(type, from: JSONSerialization.data(withJSONObject: json))
            let encoded = try JSONSerialization.jsonObject(with: encoder.encode(value)) as? [String: Any]
            precondition(encoded?["created_at"] != nil && encoded?["createdAt"] == nil)
            return value
        }
        let profile = try row(ProfileDTO.self, ["display_name": "Test", "job_title": "Designer"])
        precondition(profile.displayName == "Test" && profile.avatarUrl == nil && profile.jobTitle == "Designer")
        let category = try row(CategoryDTO.self, ["slug": "board_games", "name": "Board Games", "sf_symbol": "dice.fill"])
        precondition(category.slug == "board_games" && category.sfSymbol == "dice.fill")
        let activity = try row(ActivityDTO.self, ["author_id": id, "category_id": id, "title": "Test", "description": "", "start_at": date, "location_name": "Court", "max_participants": 12])
        precondition(activity.maxParticipants == 12 && activity.endAt == nil && activity.authorId == profile.id)
        let participant = try row(ActivityParticipantDTO.self, ["activity_id": id, "user_id": id, "status": "going"])
        precondition(participant.status == .going)
        _ = try row(CommentDTO.self, ["activity_id": id, "author_id": id, "body": "Hello"])
        _ = try row(ActivityPhotoDTO.self, ["activity_id": id, "uploader_id": id, "storage_path": "test/photo.jpg"])
        let mention = try row(ActivityMentionDTO.self, ["activity_id": id, "mentioned_user_id": id, "mentioned_by_user_id": id])
        precondition(mention.commentId == nil)
        let notification = try row(NotificationDTO.self, ["user_id": id, "type": "invite", "title": "Invite", "body": "Hello", "is_read": false])
        precondition(!notification.isRead && notification.actorUserId == nil)
        print("Configuration rejection/acceptance and all eight DTO coding checks passed")
    }
}
