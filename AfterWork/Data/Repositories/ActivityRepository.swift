import Foundation
import Supabase

@MainActor
struct ActivityRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) { self.client = client }

    func fetchUpcomingActivities(from date: Date = .now, limit: Int = 50) async throws -> [ActivityDTO] {
        do {
            return try await client.from("activities")
                .select()
                .gte("start_at", value: date.ISO8601Format())
                .order("start_at")
                .order("id")
                .limit(min(max(limit, 1), 100))
                .execute().value
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            throw DatabaseError.requestFailed
        }
    }

    // A missing or RLS-invisible row returns nil.
    func fetchActivity(id: UUID) async throws -> ActivityDTO? {
        do {
            let rows: [ActivityDTO] = try await client.from("activities")
                .select().eq("id", value: id.uuidString).limit(1).execute().value
            return rows.first
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            throw DatabaseError.requestFailed
        }
    }
}
