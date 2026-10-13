import Supabase

@MainActor
final class SupabaseManager {
    static let shared = SupabaseManager()
    private var cachedClient: SupabaseClient?

    private init() {}

    // Lazy and throwing: launching the mock UI never needs configuration or a connection.
    var client: SupabaseClient {
        get throws {
            if let cachedClient { return cachedClient }
            let configuration = try SupabaseConfiguration.load()
            let client = SupabaseClient(
                supabaseURL: configuration.url,
                supabaseKey: configuration.publicKey,
                options: .init(auth: .init(flowType: .pkce, emitLocalSessionAsInitialSession: true))
            )
            cachedClient = client
            return client
        }
    }
}
