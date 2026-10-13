import Foundation
import OSLog
import Supabase

@MainActor
struct CommentRepository {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AfterWork", category: "CommentRepository")
    private let client: SupabaseClient
    private let currentUserID: () async throws -> UUID

    init(client: SupabaseClient, currentUserID: (() async throws -> UUID)? = nil) {
        self.client = client
        self.currentUserID = currentUserID ?? { try await client.auth.session.user.id }
    }

    func fetchComments(activityId: UUID) async throws -> [Comment] {
        try await perform {
            let rows: [CommentDTO] = try await client.from("comments")
                .select("*,author:profiles!comments_author_id_fkey(id,display_name,avatar_url)")
                .eq("activity_id", value: activityId.uuidString)
                .order("created_at").execute().value
            return rows.map(Comment.init(dto:))
        }
    }

    func createComment(activityId: UUID, body: String) async throws -> Comment {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= CommentRules.maximumLength else {
            throw CommentError.invalidBody
        }
        let authorID = try await currentUserID()
        struct Insert: Encodable { let activity_id: UUID; let author_id: UUID; let body: String }
        return try await perform {
            let rows: [CommentDTO] = try await client.from("comments")
                .insert(Insert(activity_id: activityId, author_id: authorID, body: trimmed))
                .select("*,author:profiles!comments_author_id_fkey(id,display_name,avatar_url)").execute().value
            guard let row = rows.first else { throw CommentError.requestFailed }
            return Comment(dto: row)
        }
    }

    func updateComment(commentId: UUID, body: String) async throws -> Comment {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= CommentRules.maximumLength else {
            throw CommentError.invalidBody
        }
        return try await perform({
            let rows: [CommentDTO] = try await client.from("comments")
                .update(CommentUpdatePayload(body: trimmed)).eq("id", value: commentId.uuidString)
                .select("*,author:profiles!comments_author_id_fkey(id,display_name,avatar_url)").execute().value
            guard let row = rows.first else { throw CommentError.notOwner }
            return Comment(dto: row)
        }, onFailure: { Self.logBackendError($0, operation: "UPDATE", commentID: commentId) })
    }

    func deleteComment(commentId: UUID) async throws {
        struct Deleted: Decodable { let id: UUID }
        try await CommentDeleteRetry.delete(
            commentID: commentId,
            delete: { id in
                do {
                    let rows: [Deleted] = try await client.from("comments").delete()
                        .eq("id", value: id.uuidString)
                        .select("id").execute().value
                    return rows.contains(where: { $0.id == id })
                } catch {
                    #if DEBUG
                    Self.logBackendError(error, operation: "DELETE", commentID: id)
                    #endif
                    throw error
                }
            },
            exists: { id in
                do {
                    let rows: [Deleted] = try await client.from("comments")
                        .select("id").eq("id", value: id.uuidString).limit(1).execute().value
                    return rows.contains(where: { $0.id == id })
                } catch {
                    #if DEBUG
                    Self.logBackendError(error, operation: "DELETE existence check", commentID: id)
                    #endif
                    throw error
                }
            },
            log: { event in
                #if DEBUG
                switch event {
                case let .transientFailure(code):
                    Self.logger.error("Comment DELETE transient transport failure code=\(code.rawValue, privacy: .public), comment_id=\(commentId.uuidString, privacy: .public)")
                case .retryAttempted:
                    Self.logger.info("Comment DELETE retry attempted once, comment_id=\(commentId.uuidString, privacy: .public)")
                case .retrySucceeded:
                    Self.logger.info("Comment DELETE retry succeeded, comment_id=\(commentId.uuidString, privacy: .public)")
                case .retryReturnedNoRows:
                    Self.logger.info("Comment DELETE retry returned no rows, comment_id=\(commentId.uuidString, privacy: .public)")
                case let .existenceChecked(isPresent):
                    Self.logger.info("Comment DELETE existence check present=\(isPresent, privacy: .public), comment_id=\(commentId.uuidString, privacy: .public)")
                case .retryFailed:
                    Self.logger.error("Comment DELETE retry failed, comment_id=\(commentId.uuidString, privacy: .public)")
                }
                #endif
            }
        )
    }

    func createMentions(activityId: UUID, commentId: UUID, userIDs: [UUID]) async throws {
        let authorID = try await currentUserID()
        let uniqueIDs = Array(Set(userIDs)).filter { $0 != authorID }
        guard !uniqueIDs.isEmpty else { return }
        struct Insert: Encodable {
            let activity_id: UUID; let comment_id: UUID; let mentioned_user_id: UUID; let mentioned_by_user_id: UUID
        }
        try await perform {
            try await client.from("activity_mentions").insert(uniqueIDs.map {
                Insert(activity_id: activityId, comment_id: commentId, mentioned_user_id: $0, mentioned_by_user_id: authorID)
            }).execute()
        }
    }

    private func perform<T>(_ operation: () async throws -> T) async throws -> T {
        do { return try await operation() }
        catch is CancellationError { throw CancellationError() }
        catch let error as CommentError { throw error }
        catch { throw CommentError.requestFailed }
    }

    private func perform<T>(_ operation: () async throws -> T, onFailure: (Error) -> Void) async throws -> T {
        do { return try await operation() }
        catch is CancellationError { throw CancellationError() }
        catch let error as CommentError { throw error }
        catch {
            #if DEBUG
            onFailure(error)
            #endif
            throw CommentError.requestFailed
        }
    }

    private static func logBackendError(_ error: Error, operation: String, commentID: UUID) {
        if let error = error as? PostgrestError {
            let status = inferredHTTPStatus(for: error.code)
            logger.error("Comment \(operation, privacy: .public) failed: HTTP \(status.map(String.init) ?? "unavailable", privacy: .public), code=\(error.code ?? "none", privacy: .public), message=\(error.message, privacy: .public), details=\(error.details ?? "none", privacy: .public), hint=\(error.hint ?? "none", privacy: .public), comment_id=\(commentID.uuidString, privacy: .public)")
        } else if let error = error as? HTTPError,
                  let responseError = try? JSONDecoder().decode(PostgrestError.self, from: error.data) {
            logger.error("Comment \(operation, privacy: .public) failed: HTTP \(error.response.statusCode, privacy: .public), code=\(responseError.code ?? "none", privacy: .public), message=\(responseError.message, privacy: .public), details=\(responseError.details ?? "none", privacy: .public), hint=\(responseError.hint ?? "none", privacy: .public), comment_id=\(commentID.uuidString, privacy: .public)")
        } else if let error = error as? HTTPError {
            logger.error("Comment \(operation, privacy: .public) failed: HTTP \(error.response.statusCode, privacy: .public), response was not a PostgREST error body, comment_id=\(commentID.uuidString, privacy: .public)")
        } else {
            logger.error("Comment \(operation, privacy: .public) failed before a PostgREST response: \(String(describing: type(of: error)), privacy: .public), comment_id=\(commentID.uuidString, privacy: .public)")
        }
    }

    private static func inferredHTTPStatus(for code: String?) -> Int? {
        switch code {
        case "42501": 403
        case "23505": 409
        case "23503", "23514", "22P02": 400
        default: nil
        }
    }
}

enum CommentDeleteRetry {
    enum Event {
        case transientFailure(URLError.Code)
        case retryAttempted
        case retrySucceeded
        case retryReturnedNoRows
        case existenceChecked(Bool)
        case retryFailed
    }

    static func isTransientTransportError(_ error: Error) -> URLError.Code? {
        guard let urlError = error as? URLError,
              [.timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet].contains(urlError.code) else {
            return nil
        }
        return urlError.code
    }

    static func delete(
        commentID: UUID,
        delete: (UUID) async throws -> Bool,
        exists: (UUID) async throws -> Bool,
        log: (Event) -> Void = { _ in }
    ) async throws {
        do {
            if try await delete(commentID) { return }
            log(.retryReturnedNoRows)
            try await verifyMissingComment(commentID, exists: exists, log: log)
            return
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as CommentError {
            throw error
        } catch {
            guard let code = isTransientTransportError(error) else { throw CommentError.requestFailed }
            log(.transientFailure(code))
        }

        log(.retryAttempted)
        do {
            if try await delete(commentID) {
                log(.retrySucceeded)
                return
            }
            log(.retryReturnedNoRows)
            try await verifyMissingComment(commentID, exists: exists, log: log)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as CommentError {
            throw error
        } catch {
            guard isTransientTransportError(error) != nil else {
                log(.retryFailed)
                throw CommentError.requestFailed
            }
            log(.retryFailed)
            try await verifyMissingComment(commentID, exists: exists, log: log)
        }
    }

    private static func verifyMissingComment(
        _ commentID: UUID,
        exists: (UUID) async throws -> Bool,
        log: (Event) -> Void
    ) async throws {
        do {
            let isPresent = try await exists(commentID)
            log(.existenceChecked(isPresent))
            if isPresent { throw CommentError.notOwner }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as CommentError {
            throw error
        } catch {
            throw CommentError.requestFailed
        }
    }
}

struct CommentUpdatePayload: Encodable, Equatable {
    let body: String
}

enum CommentRules {
    static let maximumLength = 5000
}

enum CommentError: Error, LocalizedError, Equatable {
    case invalidBody
    case notOwner
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .invalidBody: "Comments must contain 1–5000 characters."
        case .notOwner: "You can only change your own comments."
        case .requestFailed: "We couldn't update comments. Please try again."
        }
    }
}
