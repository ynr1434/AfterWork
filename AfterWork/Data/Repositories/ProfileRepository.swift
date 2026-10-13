import Foundation
import Supabase

@MainActor
struct ProfileRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) { self.client = client }

    func fetchProfile(id: UUID) async throws -> ProfileDTO? {
        do {
            let rows: [ProfileDTO] = try await client.from("profiles")
                .select("id,email,display_name,avatar_url,department,job_title,interests,created_at,updated_at").eq("id", value: id.uuidString).limit(1).execute().value
            return rows.first
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            throw DatabaseError.requestFailed
        }
    }

    /// The RPC derives identity/email from the authenticated JWT; all fields save atomically.
    func save(_ draft: ProfileDraft) async throws -> ProfileDTO {
        guard draft.validationMessage == nil else { throw AppAuthError.invalidProfile }
        struct Parameters: Encodable {
            let p_display_name: String
            let p_department: String?
            let p_job_title: String?
            let p_interests: [String]
        }
        do {
            let rows: [ProfileDTO] = try await client.rpc("save_my_profile", params: Parameters(
                p_display_name: draft.trimmedName,
                p_department: ProfileDraft.optionalText(draft.department),
                p_job_title: ProfileDraft.optionalText(draft.jobTitle),
                p_interests: draft.interests.sorted()
            )).execute().value
            guard let profile = rows.first else { throw DatabaseError.requestFailed }
            return profile
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            throw DatabaseError.requestFailed
        }
    }
}
