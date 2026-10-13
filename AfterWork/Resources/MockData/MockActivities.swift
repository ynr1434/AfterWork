import Foundation

enum MockActivities {
    static func makeActivities(relativeTo now: Date = .now, calendar: Calendar = .current) -> [Activity] {
        let today = calendar.startOfDay(for: now)
        func start(day: Int, hour: Int, minute: Int = 0) -> Date {
            let date = calendar.date(byAdding: .day, value: day, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
        }
        // Use the nearest Friday, including today when it is Friday.
        let daysUntilFriday = (6 - calendar.component(.weekday, from: today) + 7) % 7
        let friday = daysUntilFriday
        return [
            Activity(id: UUID(uuidString: "50000000-0000-0000-0000-000000000001")!, authorId: UUID(uuidString: "60000000-0000-0000-0000-000000000001")!, categoryId: UUID(uuidString: "70000000-0000-0000-0000-000000000001")!, title: "Volleyball", description: "Close the laptop. Hit the court. All skill levels welcome — just bring your trainers.", category: .sports, startsAt: start(day: 0, hour: 19), locationName: "Riverside Sports Hall", participantCount: 8, maxParticipants: 12, organizerName: "Yernar", organizerInitials: "YN", participantInitials: ["YN", "AA", "DN"]),
            Activity(id: UUID(uuidString: "50000000-0000-0000-0000-000000000002")!, authorId: UUID(uuidString: "60000000-0000-0000-0000-000000000001")!, categoryId: UUID(uuidString: "70000000-0000-0000-0000-000000000002")!, title: "Basketball 3x3", description: "A friendly game with the team. We'll mix up the sides when everyone arrives.", category: .sports, startsAt: start(day: 0, hour: 20, minute: 30), locationName: "Central Park Court", participantCount: 4, maxParticipants: 6, organizerName: "Daniyar", organizerInitials: "DN", participantInitials: ["DN", "AS", "MK"]),
            Activity(id: UUID(uuidString: "50000000-0000-0000-0000-000000000003")!, authorId: UUID(uuidString: "60000000-0000-0000-0000-000000000001")!, categoryId: UUID(uuidString: "70000000-0000-0000-0000-000000000003")!, title: "PlayStation Night", description: "Controllers ready? Join us for a few casual matches and snacks.", category: .games, startsAt: start(day: 0, hour: 19, minute: 30), locationName: "Office Lounge · Floor 3", participantCount: 5, maxParticipants: 8, organizerName: "Arman", organizerInitials: "AA", participantInitials: ["AA", "YN", "SK"]),
            Activity(id: UUID(uuidString: "50000000-0000-0000-0000-000000000004")!, authorId: UUID(uuidString: "60000000-0000-0000-0000-000000000001")!, categoryId: UUID(uuidString: "70000000-0000-0000-0000-000000000004")!, title: "Ramen After Work", description: "Warm bowls and good company. Let's try the new spot around the corner.", category: .food, startsAt: start(day: 1, hour: 19), locationName: "Nori Ramen Bar", participantCount: 4, maxParticipants: 6, organizerName: "Aigerim", organizerInitials: "AK", participantInitials: ["AK", "ML", "YN"]),
            Activity(id: UUID(uuidString: "50000000-0000-0000-0000-000000000005")!, authorId: UUID(uuidString: "60000000-0000-0000-0000-000000000001")!, categoryId: UUID(uuidString: "70000000-0000-0000-0000-000000000005")!, title: "Movie Night", description: "Popcorn, a big screen, and a break from the workday. Meet in the lobby.", category: .movies, startsAt: start(day: 1, hour: 20), locationName: "City Cinema", participantCount: 6, maxParticipants: nil, organizerName: "Mira", organizerInitials: "ML", participantInitials: ["ML", "DN", "AK"]),
            Activity(id: UUID(uuidString: "50000000-0000-0000-0000-000000000006")!, authorId: UUID(uuidString: "60000000-0000-0000-0000-000000000001")!, categoryId: UUID(uuidString: "70000000-0000-0000-0000-000000000006")!, title: "Board Games", description: "An easygoing evening of strategy and laughs. New players are always welcome.", category: .boardGames, startsAt: start(day: friday, hour: 19, minute: 30), locationName: "The Common Room", participantCount: 7, maxParticipants: 10, organizerName: "Sam", organizerInitials: "SK", participantInitials: ["SK", "AA", "ML"])
        ]
    }

    static let activities = makeActivities()
    static var preview: Activity { activities[0] }
}
