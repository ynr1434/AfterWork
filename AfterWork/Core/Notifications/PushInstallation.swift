import Foundation
import Security

nonisolated struct PushInstallation: Codable, Sendable {
  let id: UUID
  let secret: String

  static func load() throws -> Self {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.kingz.AfterWork.push-installation",
      kSecAttrAccount as String: "installation",
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(
      query.merging([kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]) {
        _, v in v
      } as CFDictionary, &result)
    if status == errSecSuccess, let data = result as? Data,
      let value = try? JSONDecoder().decode(Self.self, from: data)
    {
      return value
    }
    guard status == errSecItemNotFound else { throw PushError.installation }
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      throw PushError.installation
    }
    let value = Self(id: UUID(), secret: bytes.map { String(format: "%02x", $0) }.joined())
    let attributes = query.merging([
      kSecValueData as String: try JSONEncoder().encode(value),
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]) { _, v in v }
    guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else {
      throw PushError.installation
    }
    return value
  }
}
