import SwiftUI

enum ActivityCategory: String, CaseIterable, Identifiable {
    case sports, games, food, drinks, movies, music, walking, creative, learning, boardGames, party, other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sports: "Sports"
        case .games: "Games"
        case .food: "Food"
        case .drinks: "Drinks"
        case .movies: "Movies"
        case .music: "Music"
        case .walking: "Walking"
        case .creative: "Creative"
        case .learning: "Learning"
        case .boardGames: "Board Games"
        case .party: "Party"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .sports: "figure.volleyball"
        case .games: "gamecontroller.fill"
        case .food: "fork.knife"
        case .drinks: "cup.and.saucer.fill"
        case .movies: "film.fill"
        case .music: "music.note"
        case .walking: "figure.walk"
        case .creative: "paintpalette.fill"
        case .learning: "book.fill"
        case .boardGames: "dice.fill"
        case .party: "party.popper.fill"
        case .other: "sparkles"
        }
    }

    // Decorative cover tints only; text uses semantic foreground colors.
    var coverColor: Color {
        switch self {
        case .sports: .orange
        case .games: .indigo
        case .food: .pink
        case .drinks: .brown
        case .movies: .purple
        case .music: .pink
        case .walking: .green
        case .creative: .teal
        case .learning: .blue
        case .boardGames: .mint
        case .party: .purple
        case .other: .blue
        }
    }
}
