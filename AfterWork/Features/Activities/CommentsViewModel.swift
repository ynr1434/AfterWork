import Foundation
import Observation

struct MentionSuggestion: Identifiable {
    let profile: ProfileDTO
    var id: UUID { profile.id }
    var name: String { profile.displayName }
    var initials: String { profile.initials }
}

enum MentionComposer {
    static func query(in text: String) -> String? {
        let token = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).last.map(String.init) ?? ""
        guard token.first == "@" else { return nil }
        return String(token.dropFirst())
    }

    static func insert(_ suggestion: MentionSuggestion, into text: String) -> String {
        let parts = text.split(separator: " ", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.last?.first == "@" else { return text + "@\(suggestion.name) " }
        var copy = parts.map(String.init)
        copy[copy.count - 1] = "@\(suggestion.name)"
        return copy.joined(separator: " ") + " "
    }

    static func uniqueUserIDs(_ ids: [UUID]) -> [UUID] { Array(Set(ids)) }
}

@MainActor @Observable
final class CommentsViewModel {
    private(set) var comments: [Comment] = []
    private(set) var suggestions: [MentionSuggestion] = []
    private(set) var isLoading = false
    private(set) var isSending = false
    var draft = ""
    var editingComment: Comment?
    var pendingDelete: Comment?
    var errorMessage: String?
    private var selectedMentionIDs: [String: UUID] = [:]
    private var suggestionTask: Task<Void, Never>?
    private let commentsRepository: CommentRepository?
    private let profilesRepository: ProfileRepository?

    init(commentsRepository: CommentRepository? = nil, profilesRepository: ProfileRepository? = nil) {
        self.commentsRepository = commentsRepository ?? (try? CommentRepository(client: SupabaseManager.shared.client))
        self.profilesRepository = profilesRepository ?? (try? ProfileRepository(client: SupabaseManager.shared.client))
    }

    func load(activityID: UUID) async {
        guard !isLoading else { return }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        guard let commentsRepository else { errorMessage = DatabaseError.notConfigured.localizedDescription; isLoading = false; return }
        do { comments = try await commentsRepository.fetchComments(activityId: activityID) }
        catch { errorMessage = error.localizedDescription }
    }

    func updateSuggestions() {
        suggestionTask?.cancel()
        guard let query = MentionComposer.query(in: draft), !query.isEmpty else {
            suggestions = []; return
        }
        suggestionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled, let self else { return }
            guard let profilesRepository else { suggestions = []; return }
            do { suggestions = try await profilesRepository.searchProfiles(query: query).map(MentionSuggestion.init(profile:)) }
            catch { suggestions = []; errorMessage = "We couldn't load coworker suggestions." }
        }
    }

    func selectSuggestion(_ suggestion: MentionSuggestion) {
        draft = MentionComposer.insert(suggestion, into: draft)
        selectedMentionIDs[suggestion.name] = suggestion.id
        suggestions = []
    }

    func beginEditing(_ comment: Comment) {
        editingComment = comment; draft = comment.body; selectedMentionIDs = [:]; suggestions = []; errorMessage = nil
    }

    func cancelEditing() { editingComment = nil; draft = ""; selectedMentionIDs = [:]; suggestions = [] }

    func submit(activityID: UUID) async {
        guard !isSending else { return }
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= CommentRules.maximumLength else {
            errorMessage = CommentError.invalidBody.localizedDescription; return
        }
        isSending = true; errorMessage = nil
        defer { isSending = false }
        guard let commentsRepository else { errorMessage = DatabaseError.notConfigured.localizedDescription; isSending = false; return }
        do {
            if let editingComment {
                let updated = try await commentsRepository.updateComment(commentId: editingComment.id, body: trimmed)
                if let index = comments.firstIndex(where: { $0.id == updated.id }) { comments[index] = updated }
            } else {
                let created = try await commentsRepository.createComment(activityId: activityID, body: trimmed)
                comments.append(created)
                do { try await commentsRepository.createMentions(activityId: activityID, commentId: created.id,
                                                                   userIDs: selectedMentionIDs.compactMap { name, id in
                                                                       trimmed.contains("@\(name)") ? id : nil
                                                                   }) }
                catch { errorMessage = "Comment posted, but mentions could not be saved." }
            }
            cancelEditing()
        } catch { errorMessage = error.localizedDescription }
    }

    func delete(_ comment: Comment) async {
        guard !isSending else { return }
        guard let commentsRepository else { errorMessage = DatabaseError.notConfigured.localizedDescription; self.pendingDelete = nil; return }
        isSending = true; errorMessage = nil
        defer { isSending = false }
        do {
            try await commentsRepository.deleteComment(commentId: comment.id)
            comments.removeAll { $0.id == comment.id }
        } catch { errorMessage = error.localizedDescription }
    }
}
