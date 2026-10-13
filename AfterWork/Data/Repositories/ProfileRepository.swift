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

    func searchProfiles(query: String, limit: Int = 8) async throws -> [ProfileDTO] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        do {
            return try await client.from("profiles")
                .select("id,email,display_name,avatar_url,department,job_title,interests,created_at,updated_at")
                .ilike("display_name", pattern: "(trimmed)%")
                .order("display_name").limit(limit).execute().value
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

            enum CodingKeys: String, CodingKey {
                case p_display_name, p_department, p_job_title, p_interests
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(p_display_name, forKey: .p_display_name)
                if let p_department {
                    try container.encode(p_department, forKey: .p_department)
                } else {
                    try container.encodeNil(forKey: .p_department)
                }
                if let p_job_title {
                    try container.encode(p_job_title, forKey: .p_job_title)
                } else {
                    try container.encodeNil(forKey: .p_job_title)
                }
                try container.encode(p_interests, forKey: .p_interests)
            }
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
