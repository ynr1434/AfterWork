import Foundation

struct SupabaseConfiguration {
    let url: URL
    let publicKey: String

    static func load(from bundle: Bundle = .main) throws -> SupabaseConfiguration {
        try load(values: bundle.infoDictionary ?? [:])
    }

    static func load(values: [String: Any]) throws -> SupabaseConfiguration {
        guard let rawURL = values["SUPABASE_URL"] as? String,
              let rawKey = values["SUPABASE_ANON_KEY"] as? String else {
            throw DatabaseError.notConfigured
        }
        let urlString = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty, !key.isEmpty,
              !urlString.contains("$("), !key.contains("$(") else {
            throw DatabaseError.notConfigured
        }
        guard let url = URL(string: urlString), url.scheme == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else {
            throw DatabaseError.invalidConfiguration
        }
        // Defense against accidentally embedding a server secret. JWT inspection
        // here is configuration validation, not authentication or signature verification.
        guard isPublicClientKey(key) else { throw DatabaseError.invalidConfiguration }
        return SupabaseConfiguration(url: url, publicKey: key)
    }

    private static func isPublicClientKey(_ key: String) -> Bool {
        if key.hasPrefix("sb_publishable_") {
            return key.count > "sb_publishable_".count && !key.contains(where: \.isWhitespace)
        }
        let segments = key.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { return false }
        var payload = String(segments[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return json["role"] as? String == "anon"
    }
}
