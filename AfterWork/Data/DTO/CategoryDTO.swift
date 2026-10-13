import Foundation

// Database row; intentionally separate from the mock UI model.
nonisolated struct CategoryDTO: Codable, Identifiable, Sendable {
    let id: UUID
    let slug: String
    let name: String
    let sfSymbol: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case slug
        case name
        case sfSymbol = "sf_symbol"
        case createdAt = "created_at"
    }
}
