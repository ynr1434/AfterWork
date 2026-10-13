#if DEBUG
import Foundation
import Supabase

// Temporary development probe. No request is made until the user presses Test.
@MainActor
struct SupabaseConnectionChecker {
    func check() async throws -> Int {
        let client = try SupabaseManager.shared.client
        do {
            let categories: [CategoryDTO] = try await client.from("categories")
                .select().order("slug").execute().value
            guard !categories.isEmpty else { throw ConnectionError.emptyCategories }
            return categories.count
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ConnectionError {
            throw error
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw ConnectionError.requestFailed
        }
    }

    enum ConnectionError: Error, LocalizedError {
        case emptyCategories
        case requestFailed

        var errorDescription: String? {
            switch self {
            case .emptyCategories:
                "No categories returned. Verify the 12 seed rows and apply 002_public_category_read.sql."
            case .requestFailed:
                "Could not read categories. Check your network, project URL, public key, and that both SQL migrations were applied."
            }
        }
    }
}
#endif
