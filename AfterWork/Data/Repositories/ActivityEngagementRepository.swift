import Foundation
import Supabase

nonisolated struct ActivityEngagementState: Sendable {
    var isSaved = false
    var isSkipped = false
    var isGoing = false
    var participantCount: Int?
    var participantInitials: [String]?
}

@MainActor
struct ActivityEngagementRepository {
    private let client: SupabaseClient
    private let currentUserID: () async throws -> UUID

    init(client: SupabaseClient, currentUserID: (() async throws -> UUID)? = nil) {
        self.client = client
        self.currentUserID = currentUserID ?? { try await client.auth.session.user.id }
    }

    func fetchEngagement(activityId: UUID) async throws -> ActivityEngagementState {
        let userID = try await currentUserID()
        let actionRows: [ActivityUserActionDTO] = try await client.from("activity_user_actions")
            .select().eq("activity_id", value: activityId.uuidString)
            .eq("user_id", value: userID.uuidString).limit(1).execute().value
        let participants = try await fetchParticipantRows(activityId: activityId)
        return state(actionRows.first, participants: participants, userID: userID)
    }

    func fetchEngagements(activityIds: [UUID]) async throws -> [UUID: ActivityEngagementState] {
        guard !activityIds.isEmpty else { return [:] }
        let userID = try await currentUserID()
        let values = activityIds.map(\.uuidString)
        let actions: [ActivityUserActionDTO] = try await client.from("activity_user_actions")
            .select().in("activity_id", values: values).eq("user_id", value: userID.uuidString).execute().value
        let goingRows: [ActivityParticipantDTO] = try await client.from("activity_participants")
            .select().in("activity_id", values: values).eq("user_id", value: userID.uuidString)
            .eq("status", value: "going").execute().value
        let goingIDs = Set(goingRows.map(\.activityId))
        let participantRows: [ParticipantDTO] = try await client.from("activity_participants")
            .select("id,activity_id,user_id,status,profile:profiles!activity_participants_user_id_fkey(id,display_name,job_title,department)")
            .in("activity_id", values: values).eq("status", value: "going").execute().value
        var initialsByActivity: [UUID: [String]] = [:]
        for participant in participantRows { initialsByActivity[participant.activityId, default: []].append(participant.initials) }
        var result = Dictionary(uniqueKeysWithValues: activityIds.map { ($0, ActivityEngagementState()) })
        for action in actions {
            result[action.activityId] = ActivityEngagementState(isSaved: action.isSaved, isSkipped: action.isSkipped,
                                                                 isGoing: goingIDs.contains(action.activityId),
                                                                 participantInitials: initialsByActivity[action.activityId])
        }
        for id in activityIds {
            if result[id]?.participantInitials == nil {
                result[id]?.participantInitials = initialsByActivity[id]
                result[id]?.isGoing = goingIDs.contains(id)
            }
        }
        return result
    }

    func setSaved(activityId: UUID, isSaved: Bool) async throws -> ActivityEngagementState {
        let current = try await fetchAction(activityId: activityId)
        return try await upsertAction(activityId: activityId, isSaved: isSaved, isSkipped: current?.isSkipped ?? false)
    }

    func setSkipped(activityId: UUID, isSkipped: Bool) async throws -> ActivityEngagementState {
        let current = try await fetchAction(activityId: activityId)
        return try await upsertAction(activityId: activityId, isSaved: current?.isSaved ?? false, isSkipped: isSkipped)
    }

    func joinActivity(activityId: UUID) async throws -> ActivityEngagementState {
        struct Parameters: Encodable { let p_activity_id: UUID }
        struct Result: Decodable { let activityId: UUID; let participantCount: Int
            enum CodingKeys: String, CodingKey { case activityId = "activity_id"; case participantCount = "participant_count" }
        }
        do {
            let rows: [Result] = try await client.rpc("join_activity", params: Parameters(p_activity_id: activityId)).execute().value
            guard let row = rows.first else { throw ActivityError.requestFailed }
            let action = try await fetchAction(activityId: activityId)
            return ActivityEngagementState(isSaved: action?.isSaved ?? false, isSkipped: action?.isSkipped ?? false,
                                           isGoing: true, participantCount: row.participantCount,
                                           participantInitials: nil)
        } catch let error as PostgrestError where error.code == "P0001" {
            throw ActivityError.full
        } catch let error as PostgrestError where ["PGRST301", "PGRST303"].contains(error.code ?? "") {
            throw ActivityError.signInRequired
        } catch { throw error }
    }

    func leaveActivity(activityId: UUID) async throws -> ActivityEngagementState {
        let userID = try await currentUserID()
        try await client.from("activity_participants").delete()
            .eq("activity_id", value: activityId.uuidString).eq("user_id", value: userID.uuidString)
            .execute()
        let action = try await fetchAction(activityId: activityId)
        let participants = try await fetchParticipantRows(activityId: activityId)
        return ActivityEngagementState(isSaved: action?.isSaved ?? false, isSkipped: action?.isSkipped ?? false,
                                       isGoing: false, participantCount: participants.count,
                                       participantInitials: participants.map(\.initials))
    }

    func fetchParticipants(activityId: UUID) async throws -> [ParticipantDTO] {
        try await fetchParticipantRows(activityId: activityId)
    }

    func fetchGoingCount(activityId: UUID) async throws -> Int {
        let rows = try await fetchParticipantRows(activityId: activityId)
        return rows.count
    }

    func fetchSavedActivityIDs() async throws -> [UUID] {
        let userID = try await currentUserID()
        let rows: [ActivityUserActionDTO] = try await client.from("activity_user_actions")
            .select().eq("user_id", value: userID.uuidString).eq("is_saved", value: "true").execute().value
        return rows.map(\.activityId)
    }

    func fetchJoinedActivityIDs() async throws -> [UUID] {
        let userID = try await currentUserID()
        let rows: [ActivityParticipantDTO] = try await client.from("activity_participants")
            .select().eq("user_id", value: userID.uuidString).eq("status", value: "going").execute().value
        return rows.map(\.activityId)
    }

    private func fetchAction(activityId: UUID) async throws -> ActivityUserActionDTO? {
        let userID = try await currentUserID()
        let rows: [ActivityUserActionDTO] = try await client.from("activity_user_actions")
            .select().eq("activity_id", value: activityId.uuidString)
            .eq("user_id", value: userID.uuidString).limit(1).execute().value
        return rows.first
    }

    private func upsertAction(activityId: UUID, isSaved: Bool, isSkipped: Bool) async throws -> ActivityEngagementState {
        let userID = try await currentUserID()
        struct Payload: Encodable {
            let activity_id: UUID; let user_id: UUID; let is_saved: Bool; let is_skipped: Bool
        }
        let _: ActivityUserActionDTO = try await client.from("activity_user_actions")
            .upsert(Payload(activity_id: activityId, user_id: userID, is_saved: isSaved, is_skipped: isSkipped),
                    onConflict: "activity_id,user_id").select().single().execute().value
        let participants = try await fetchParticipantRows(activityId: activityId)
        return ActivityEngagementState(isSaved: isSaved, isSkipped: isSkipped,
                                       isGoing: participants.contains { $0.userId == userID && $0.status == .going },
                                       participantCount: participants.count,
                                       participantInitials: participants.map(\.initials))
    }

    private func fetchParticipantRows(activityId: UUID) async throws -> [ParticipantDTO] {
        try await client.from("activity_participants")
            .select("id,activity_id,user_id,status,profile:profiles!activity_participants_user_id_fkey(id,display_name,job_title,department)")
            .eq("activity_id", value: activityId.uuidString).eq("status", value: "going").execute().value
    }

    private func state(_ action: ActivityUserActionDTO?, participants: [ParticipantDTO], userID: UUID) -> ActivityEngagementState {
        ActivityEngagementState(isSaved: action?.isSaved ?? false, isSkipped: action?.isSkipped ?? false,
                                 isGoing: participants.contains { $0.userId == userID && $0.status == .going },
                                 participantCount: participants.count)
    }
}
