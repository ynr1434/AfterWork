import Foundation

nonisolated enum DatabaseError: Error, LocalizedError {
    case notConfigured
    case invalidConfiguration
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured: "The backend is not configured yet."
        case .invalidConfiguration: "Check the backend URL and public client key."
        case .requestFailed: "We couldn't load this information. Please try again."
        }
    }
}
