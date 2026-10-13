import Foundation
import Supabase

@MainActor
struct ProfileRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) { self.client = client }

    func fetchProfile(id: UUID) async throws -> ProfileDTO? {
        do {
            let rows: [ProfileDTO] = try await client.from("profiles")
                .select().eq("id", value: id.uuidString).limit(1).execute().value
            return rows.first
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            throw DatabaseError.requestFailed
        }
    }
}
