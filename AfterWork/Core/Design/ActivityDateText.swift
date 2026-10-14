import Foundation

/// Display-only formatting. Stored instants and backend UTC values are unchanged.
enum ActivityDateText {
    static func schedule(_ date: Date, now: Date = .now, calendar: Calendar = .current,
                         locale: Locale = .current) -> String {
        let format = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let day: String
        if calendar.isDate(date, inSameDayAs: now) { day = "Today" }
        else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            day = "Tomorrow"
        } else { day = date.formatted(format.weekday(.wide).month(.abbreviated).day()) }
        return "\(day) · \(date.formatted(format.hour().minute()))"
    }
}
