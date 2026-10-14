import Foundation

/// Reads the XML entitlement slot of this executable's own code signature.
/// SecTask entitlement APIs are not public iOS SDK APIs. Never infer from DEBUG,
/// receipt type, or an unsigned Info.plist setting. Missing/DER-only signatures fail closed.
nonisolated enum SigningEntitlements {
  static func apnsEnvironment(bundle: Bundle = .main) -> APNsEnvironment? {
    guard let url = bundle.executableURL,
      let data = try? Data(contentsOf: url, options: .mappedIfSafe),
      let value = entitlements(in: data)?["aps-environment"] as? String
    else { return nil }
    return APNsEnvironment(entitlement: value)
  }

  static func entitlements(in data: Data) -> [String: Any]? {
    func number(_ offset: Int, big: Bool = false) -> Int? {
      guard offset >= 0, offset <= data.count - 4 else { return nil }
      let bytes = Array(data[offset..<offset + 4])
      return (big ? bytes : bytes.reversed()).reduce(0) { ($0 << 8) | Int($1) }
    }
    guard number(0) == 0xfeed_facf, let count = number(16), count <= 4096 else { return nil }
    var cursor = 32
    for _ in 0..<count {
      guard let command = number(cursor), let size = number(cursor + 4), size >= 8,
        cursor <= data.count - size
      else { return nil }
      if command == 0x1d {  // LC_CODE_SIGNATURE, linkedit_data_command
        guard size >= 16, let offset = number(cursor + 8), let length = number(cursor + 12),
          length >= 12, offset <= data.count - length,
          number(offset, big: true) == 0xfade_0cc0,
          let slots = number(offset + 8, big: true), slots <= (length - 12) / 8
        else { return nil }
        for slot in 0..<slots {
          let index = offset + 12 + slot * 8
          guard let type = number(index, big: true), let relative = number(index + 4, big: true),
            relative >= 12, relative <= length - 8
          else { return nil }
          if type == 5 {  // CSSLOT_ENTITLEMENTS / CSMAGIC_EMBEDDED_ENTITLEMENTS
            let blob = offset + relative
            guard number(blob, big: true) == 0xfade_7171, let size = number(blob + 4, big: true),
              size >= 8, size <= length - relative
            else { return nil }
            return
              (try? PropertyListSerialization.propertyList(
                from: data.subdata(in: blob + 8..<blob + size), format: nil)) as? [String: Any]
          }
        }
        return nil
      }
      cursor += size
    }
    return nil
  }
}
