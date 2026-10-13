import Foundation

struct Activity: Identifiable {
    let id: UUID
    let authorId: UUID
    let categoryId: UUID
    let title: String
    let description: String
    let category: ActivityCategory
    // A single date holds both the local day and start time.
    let startsAt: Date
    let locationName: String
    let participantCount: Int
    let maxParticipants: Int?
    let organizerName: String
    let organizerInitials: String
    let participantInitials: [String]
    var imageName: String? = nil
    var endsAt: Date? = nil
    var locationAddress: String? = nil
    var coverImageURL: String? = nil
    var categoryName: String? = nil

    var categoryDisplayName: String { categoryName ?? category.displayName }

    var scheduleText: String {
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(startsAt) {
            day = "Today"
        } else if calendar.isDateInTomorrow(startsAt) {
            day = "Tomorrow"
        } else {
            day = startsAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        }
        return "\(day) · \(startsAt.formatted(date: .omitted, time: .shortened))"
    }

    var participationText: String {
        if let maxParticipants {
            return "\(participantCount) of \(maxParticipants) going"
        }
        return "\(participantCount) going"
    }
}
