import Foundation

/// One PostgREST relational response: activity row plus small embedded projections.
nonisolated struct ActivityRecordDTO: Decodable {
    struct Organizer: Decodable {
        let id: UUID
        let displayName: String
        enum CodingKeys: String, CodingKey { case id; case displayName = "display_name" }
    }
    struct AttendanceCount: Decodable { let count: Int }
    let row: ActivityDTO
    let category: CategoryDTO?
    let organizer: Organizer?
    let going: [AttendanceCount]

    enum CodingKeys: String, CodingKey { case category, organizer, going }
    init(from decoder: Decoder) throws {
        row = try ActivityDTO(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        category = try container.decodeIfPresent(CategoryDTO.self, forKey: .category)
        organizer = try container.decodeIfPresent(Organizer.self, forKey: .organizer)
        going = try container.decode([AttendanceCount].self, forKey: .going)
    }

    @MainActor
    func activity() -> Activity {
        let name = organizer?.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let organizerName = name.flatMap { $0.isEmpty ? nil : $0 } ?? "Organizer unavailable"
        let initials = name?.split(whereSeparator: \.isWhitespace).prefix(2)
            .compactMap { $0.first.map(String.init) }.joined().uppercased() ?? ""
        return Activity(
            id: row.id, authorId: row.authorId, categoryId: row.categoryId,
            title: row.title, description: row.description,
            category: ActivityCategory(databaseSlug: category?.slug ?? "other"),
            startsAt: row.startAt, locationName: row.locationName,
            participantCount: going.first?.count ?? 0, maxParticipants: row.maxParticipants,
            organizerName: organizerName, organizerInitials: initials,
            participantInitials: [], endsAt: row.endAt, locationAddress: row.locationAddress,
            coverImageURL: row.coverImageUrl, categoryName: category?.name
        )
    }
}
