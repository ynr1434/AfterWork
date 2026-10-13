import Foundation
import Supabase

@MainActor
struct ActivityRepository {
    private let client: SupabaseClient
    private let currentUserID: () async throws -> UUID

    init(client: SupabaseClient, currentUserID: (() async throws -> UUID)? = nil) {
        self.client = client
        self.currentUserID = currentUserID ?? { try await client.auth.session.user.id }
    }

    // Left embeds preserve activities with no attendees. Filtering the embed does not
    // remove the parent. Count aggregation avoids payload truncation and N+1 requests.
    static let selection = """
    *,category:categories!activities_category_id_fkey(*),\
    organizer:profiles!activities_author_id_fkey(id,display_name),\
    going:activity_participants!activity_participants_activity_id_fkey(count)
    """

    func fetchCategories() async throws -> [CategoryDTO] {
        try await perform {
            let rows: [CategoryDTO] = try await client.from("categories").select().order("name").execute().value
            guard !rows.isEmpty else { throw ActivityError.categoriesUnavailable }
            return rows
        }
    }

    func fetchUpcomingActivities(from date: Date = .now, categoryId: UUID? = nil,
                                 offset: Int = 0, limit: Int = 50) async throws -> [Activity] {
        try await perform {
            var query = client.from("activities").select(Self.selection)
                .eq("going.status", value: "going")
                .gte("start_at", value: date.ISO8601Format())
            if let categoryId { query = query.eq("category_id", value: categoryId.uuidString) }
            let start = max(0, offset)
            let rows: [ActivityRecordDTO] = try await query.order("start_at").order("id")
                .range(from: start, to: start + min(max(limit, 1), 100) - 1).execute().value
            return rows.map { $0.activity() }
        }
    }

    func fetchActivitiesByCategory(categoryId: UUID, from date: Date = .now) async throws -> [Activity] {
        try await fetchUpcomingActivities(from: date, categoryId: categoryId)
    }

    func fetchActivity(id: UUID) async throws -> Activity? {
        try await perform {
            let rows: [ActivityRecordDTO] = try await client.from("activities").select(Self.selection)
                .eq("id", value: id.uuidString).eq("going.status", value: "going").limit(1).execute().value
            return rows.first?.activity()
        }
    }

    func fetchActivities(ids: [UUID]) async throws -> [Activity] {
        guard !ids.isEmpty else { return [] }
        return try await perform {
            let rows: [ActivityRecordDTO] = try await client.from("activities").select(Self.selection)
                .in("id", values: ids.map(\.uuidString)).eq("going.status", value: "going")
                .order("start_at").order("id").execute().value
            return rows.map { $0.activity() }
        }
    }

    func fetchActivitiesCreatedByCurrentUser(limit: Int = 50) async throws -> [Activity] {
        try await perform {
            let userID = try await currentUserID()
            let rows: [ActivityRecordDTO] = try await client.from("activities").select(Self.selection)
                .eq("author_id", value: userID.uuidString).eq("going.status", value: "going")
                .order("start_at").order("id").limit(min(max(limit, 1), 100)).execute().value
            return rows.map { $0.activity() }
        }
    }

    func createActivity(_ draft: ActivityDraft, id: UUID = UUID()) async throws -> Activity {
        let request = {
            let values = try ActivityValues(draft)
            let authorID = try await currentUserID()
            struct Creation: Encodable {
                let id: UUID
                let author_id: UUID
                let values: ActivityValues
                func encode(to encoder: Encoder) throws {
                    try values.encode(to: encoder)
                    var container = encoder.container(keyedBy: Key.self)
                    try container.encode(id, forKey: .id)
                    try container.encode(author_id, forKey: .author_id)
                }
                enum Key: String, CodingKey { case id, author_id }
            }
            let rows: [ActivityRecordDTO] = try await client.from("activities")
                .insert(Creation(id: id, author_id: authorID, values: values))
                .select(Self.selection).execute().value
            guard let result = rows.first, result.row.authorId == authorID else { throw ActivityError.requestFailed }
            return result.activity()
        }
        do { return try await perform(request) }
        catch ActivityError.network {
            #if DEBUG
            print("[AfterWork] retrying idempotent activity create once")
            #endif
            try await Task.sleep(nanoseconds: 250_000_000)
            do { return try await perform(request) }
            catch ActivityError.duplicatePrimaryKey {
                return try await recoverCreatedActivity(id: id, authorID: try await currentUserID())
            }
        }
        catch ActivityError.duplicatePrimaryKey {
            return try await recoverCreatedActivity(id: id, authorID: try await currentUserID())
        }
    }

    private func recoverCreatedActivity(id: UUID, authorID: UUID) async throws -> Activity {
        guard let activity = try await fetchActivity(id: id) else { throw ActivityError.requestFailed }
        guard activity.authorId == authorID else { throw ActivityError.notOwner }
        return activity
    }

    func updateActivity(id: UUID, draft: ActivityDraft) async throws -> Activity {
        try await perform {
            let values = try ActivityValues(draft)
            let authorID = try await currentUserID()
            let rows: [ActivityRecordDTO] = try await client.from("activities").update(values)
                .eq("id", value: id.uuidString).eq("author_id", value: authorID.uuidString)
                .eq("going.status", value: "going").select(Self.selection).execute().value
            guard let result = rows.first else { throw ActivityError.notOwner }
            return result.activity()
        }
    }

    func deleteActivity(id: UUID) async throws {
        try await perform {
            let authorID = try await currentUserID()
            struct Deleted: Decodable { let id: UUID }
            let rows: [Deleted] = try await client.from("activities").delete()
                .eq("id", value: id.uuidString).eq("author_id", value: authorID.uuidString)
                .select("id").execute().value
            guard rows.contains(where: { $0.id == id }) else { throw ActivityError.notOwner }
        }
    }

    private func perform<T>(_ operation: () async throws -> T) async throws -> T {
        do { return try await operation() }
        catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            if let error = error as? ActivityError { throw error }
            if let error = error as? DatabaseError { throw error }
            if error is Supabase.AuthError { throw ActivityError.signInRequired }
            if let error = error as? URLError {
                #if DEBUG
                print("[AfterWork] activity network error code=\(error.code.rawValue)")
                #endif
                if [.timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet].contains(error.code) {
                    throw ActivityError.network
                }
            }
            if let error = error as? PostgrestError {
                #if DEBUG
                print("[AfterWork] PostgREST error code=\(error.code ?? "nil")")
                #endif
                if ["PGRST301", "PGRST303"].contains(error.code ?? "") {
                    throw ActivityError.signInRequired
                }
                if error.code == "23505" { throw ActivityError.duplicatePrimaryKey }
                throw ActivityError.server
            }
            throw ActivityError.requestFailed
        }
    }
}


/// Only editable columns. Explicit nulls let editing clear optional values.
private nonisolated struct ActivityValues: Encodable {
    let draft: ActivityDraft
    init(_ draft: ActivityDraft) throws {
        if let error = draft.validationMessage { throw ActivityError.invalid(error) }
        self.draft = draft
    }
    enum Key: String, CodingKey {
        case title, description, category_id, start_at, end_at, location_name, location_address, max_participants
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(draft.title, forKey: .title)
        try container.encode(draft.description, forKey: .description)
        try container.encode(draft.categoryId, forKey: .category_id)
        try container.encode(draft.startsAt, forKey: .start_at)
        try container.encode(draft.hasEnd ? draft.endsAt : nil, forKey: .end_at)
        try container.encode(draft.locationName, forKey: .location_name)
        try container.encode(draft.locationAddress.isEmpty ? nil : draft.locationAddress, forKey: .location_address)
        try container.encode(draft.capacity, forKey: .max_participants)
    }
}
