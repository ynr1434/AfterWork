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
            return await resolveCoverURLs(rows.map { $0.activity() })
        }
    }

    func fetchActivitiesByCategory(categoryId: UUID, from date: Date = .now) async throws -> [Activity] {
        try await fetchUpcomingActivities(from: date, categoryId: categoryId)
    }

    func fetchActivity(id: UUID) async throws -> Activity? {
        try await perform {
            let rows: [ActivityRecordDTO] = try await client.from("activities").select(Self.selection)
                .eq("id", value: id.uuidString).eq("going.status", value: "going").limit(1).execute().value
            guard let row = rows.first else { return nil }
            return await resolveCoverURLs([row.activity()]).first
        }
    }

    func fetchActivities(ids: [UUID]) async throws -> [Activity] {
        guard !ids.isEmpty else { return [] }
        return try await perform {
            let rows: [ActivityRecordDTO] = try await client.from("activities").select(Self.selection)
                .in("id", values: ids.map(\.uuidString)).eq("going.status", value: "going")
                .order("start_at").order("id").execute().value
            return await resolveCoverURLs(rows.map { $0.activity() })
        }
    }

    func fetchActivitiesCreatedByCurrentUser(limit: Int = 50) async throws -> [Activity] {
        try await perform {
            let userID = try await currentUserID()
            let rows: [ActivityRecordDTO] = try await client.from("activities").select(Self.selection)
                .eq("author_id", value: userID.uuidString).eq("going.status", value: "going")
                .order("start_at").order("id").limit(min(max(limit, 1), 100)).execute().value
            return await resolveCoverURLs(rows.map { $0.activity() })
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
            return await resolveCoverURLs([result.activity()]).first ?? result.activity()
        }
    }

    /// Stores the selected cover in the private activity photo bucket. The metadata row
    /// keeps it subject to the same membership, ownership, and cleanup rules as gallery photos.
    func attachCoverImage(activityID: UUID, jpegData: Data) async throws -> Activity {
        let authorID = try await currentUserID()
        let current: [CoverPathDTO] = try await perform {
            try await client.from("activities").select("cover_image_url")
                .eq("id", value: activityID.uuidString)
                .eq("author_id", value: authorID.uuidString)
                .limit(1).execute().value
        }
        guard let currentRow = current.first else { throw ActivityError.notOwner }
        let currentCoverPath = currentRow.coverImageUrl

        let photoRepository = ActivityPhotoRepository(client: client)
        let photo = try await photoRepository.uploadPhoto(activityID: activityID, jpegData: jpegData)
        do {
            let rows: [ActivityRecordDTO] = try await perform {
                try await client.from("activities")
                    .update(CoverImageValue(path: photo.storagePath))
                    .eq("id", value: activityID.uuidString)
                    .eq("author_id", value: authorID.uuidString)
                    .eq("going.status", value: "going")
                    .select(Self.selection).execute().value
            }
            guard let row = rows.first else { throw ActivityError.notOwner }
            if let oldPath = currentCoverPath, oldPath != photo.storagePath {
                try? await photoRepository.deletePhoto(storagePath: oldPath)
            }
            return await resolveCoverURLs([row.activity()]).first ?? row.activity()
        } catch {
            // A lost response may follow a successful update. Confirm the stored path before
            // rolling back the just-uploaded object so the database never points to a deleted cover.
            let latest: [CoverPathDTO] = (try? await client.from("activities").select("cover_image_url")
                .eq("id", value: activityID.uuidString)
                .eq("author_id", value: authorID.uuidString)
                .limit(1).execute().value) ?? []
            if latest.first?.coverImageUrl == photo.storagePath,
               let activity = try await fetchActivity(id: activityID) {
                return activity
            }
            try? await photoRepository.deletePhoto(photoID: photo.id)
            throw error
        }
    }

    func deleteActivity(id: UUID) async throws {
        try await perform {
            let authorID = try await currentUserID()
            struct Deleted: Decodable { let id: UUID }
            // Confirm ownership before touching Storage so an unauthorized activity
            // delete cannot remove photo objects as a side effect.
            let owned: [Deleted] = try await client.from("activities").select("id")
                .eq("id", value: id.uuidString).eq("author_id", value: authorID.uuidString)
                .limit(1).execute().value
            guard owned.contains(where: { $0.id == id }) else { throw ActivityError.notOwner }

            let photos: [ActivityPhotoPath] = try await client.from("activity_photos")
                .select("storage_path").eq("activity_id", value: id.uuidString).execute().value
            if !photos.isEmpty {
                do {
                    try await client.storage.from(ActivityPhotoRepository.bucketName)
                        .remove(paths: photos.map(\.storagePath))
                } catch {
                    #if DEBUG
                    print("[AfterWork] activity photo cleanup failed, activity_id=\(id.uuidString), error_type=\(String(describing: type(of: error)))")
                    #endif
                    throw ActivityError.requestFailed
                }
            }

            let rows: [Deleted] = try await client.from("activities").delete()
                .eq("id", value: id.uuidString).eq("author_id", value: authorID.uuidString)
                .select("id").execute().value
            guard rows.contains(where: { $0.id == id }) else { throw ActivityError.notOwner }
        }
    }

    private func resolveCoverURLs(_ activities: [Activity]) async -> [Activity] {
        let storagePaths = activities.compactMap { activity -> String? in
            guard let value = activity.coverImageURL,
                  URL(string: value)?.scheme == nil,
                  value.hasPrefix("activities/\(activity.id.uuidString.lowercased())/") else { return nil }
            return value
        }
        guard !storagePaths.isEmpty else { return activities }

        var signedURLs: [String: URL] = [:]
        do {
            let results = try await client.storage.from(ActivityPhotoRepository.bucketName)
                .createSignedURLs(paths: storagePaths, expiresIn: ActivityPhotoRules.signedURLLifetimeSeconds)
            for result in results {
                if case let .success(path, url) = result { signedURLs[path] = url }
            }
        } catch {
            // Covers are optional; a Storage access issue must not hide the activity itself.
        }

        return activities.map { activity in
            guard let path = activity.coverImageURL,
                  URL(string: path)?.scheme == nil,
                  path.hasPrefix("activities/\(activity.id.uuidString.lowercased())/") else { return activity }
            var resolved = activity
            resolved.coverImageURL = signedURLs[path]?.absoluteString
            return resolved
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

private struct ActivityPhotoPath: Decodable {
    let storagePath: String
    enum CodingKeys: String, CodingKey { case storagePath = "storage_path" }
}

private struct CoverPathDTO: Decodable {
    let coverImageUrl: String?
    enum CodingKeys: String, CodingKey { case coverImageUrl = "cover_image_url" }
}

private struct CoverImageValue: Encodable {
    let coverImageUrl: String
    enum CodingKeys: String, CodingKey { case coverImageUrl = "cover_image_url" }
    init(path: String) { coverImageUrl = path }
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
