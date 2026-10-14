import Foundation
import Supabase

@MainActor
struct PushDeviceRepository {
  let client: SupabaseClient
  func register(installation: PushInstallation, token: String, environment: APNsEnvironment)
    async throws
  {
    struct Parameters: Encodable {
      let p_installation_id: UUID
      let p_installation_secret: String
      let p_device_token: String
      let p_environment: String
    }
    let _: UUID = try await client.rpc(
      "register_push_device",
      params: Parameters(
        p_installation_id: installation.id, p_installation_secret: installation.secret,
        p_device_token: token, p_environment: environment.rawValue)
    ).execute().value
  }
  func unregister(installation: PushInstallation) async throws {
    struct Parameters: Encodable {
      let p_installation_id: UUID
      let p_installation_secret: String
    }
    try await client.rpc(
      "unregister_push_device",
      params: Parameters(
        p_installation_id: installation.id, p_installation_secret: installation.secret)
    ).execute()
  }
}
