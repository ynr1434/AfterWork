import Foundation

struct Comment: Identifiable, Equatable {
    let id: UUID
    let activityId: UUID
    let authorId: UUID
    let authorName: String
    let authorInitials: String
    let body: String
    let createdAt: Date
    let updatedAt: Date

    var isEdited: Bool { updatedAt.timeIntervalSince(createdAt) > 1 }

    init(dto: CommentDTO) {
        id = dto.id
        activityId = dto.activityId
        authorId = dto.authorId
        authorName = dto.author?.displayName ?? "Coworker"
        authorInitials = dto.author?.displayName.split(whereSeparator: \.isWhitespace)
            .prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased() ?? "?"
        body = dto.body
        createdAt = dto.createdAt
        updatedAt = dto.updatedAt
    }
}
