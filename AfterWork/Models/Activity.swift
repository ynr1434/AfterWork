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
    var participantCount: Int
    let maxParticipants: Int?
    let organizerName: String
    let organizerInitials: String
    var participantInitials: [String]
    var isSaved = false
    var isSkipped = false
    var isGoing = false
    var imageName: String? = nil
    var endsAt: Date? = nil
    var locationAddress: String? = nil
    var coverImageURL: String? = nil
    var categoryName: String? = nil

    var categoryDisplayName: String { categoryName ?? category.displayName }

    var scheduleText: String {
        ActivityDateText.schedule(startsAt)
    }

    var participationText: String {
        if let maxParticipants {
            return "\(participantCount) of \(maxParticipants) going"
        }
        return "\(participantCount) going"
    }
}
