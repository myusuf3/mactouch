import CryptoKit
import Foundation

/// The signature the device attaches to a nonce-bearing identify:
/// HMAC-SHA256 with the device key over `IDENTIFY|<nonce>|<slot>`. Verifiers
/// that hold a copy of the key (the PAM module) check it here. The exact
/// construction is pinned by docs/protocol-vectors.json.
public enum ApprovalMAC {
  public static func material(nonce: String, slot: Int) -> String {
    "IDENTIFY|\(nonce.lowercased())|\(slot)"
  }

  /// Lower-case hex, 64 characters.
  public static func compute(key: Data, nonce: String, slot: Int) -> String {
    let mac = HMAC<SHA256>.authenticationCode(for: Data(material(nonce: nonce, slot: slot).utf8),
                                              using: SymmetricKey(data: key))
    return mac.map { String(format: "%02x", $0) }.joined()
  }

  /// Constant-time comparison; false for malformed hex.
  public static func verify(key: Data, nonce: String, slot: Int, mac: String) -> Bool {
    guard let presented = Data(hex: mac) else { return false }
    return HMAC<SHA256>.isValidAuthenticationCode(presented,
                                                  authenticating: Data(material(nonce: nonce, slot: slot).utf8),
                                                  using: SymmetricKey(data: key))
  }
}

extension Data {
  /// Nil unless the string is an even number of hex digits.
  public init?(hex: String) {
    let digits = Array(hex.utf8)
    guard digits.count % 2 == 0 else { return nil }
    var bytes = [UInt8](); bytes.reserveCapacity(digits.count / 2)
    var index = 0
    while index < digits.count {
      guard let high = Data.nibble(digits[index]), let low = Data.nibble(digits[index + 1]) else { return nil }
      bytes.append(high << 4 | low)
      index += 2
    }
    self.init(bytes)
  }

  private static func nibble(_ c: UInt8) -> UInt8? {
    switch c {
    case UInt8(ascii: "0")...UInt8(ascii: "9"): return c - UInt8(ascii: "0")
    case UInt8(ascii: "a")...UInt8(ascii: "f"): return c - UInt8(ascii: "a") + 10
    case UInt8(ascii: "A")...UInt8(ascii: "F"): return c - UInt8(ascii: "A") + 10
    default: return nil
    }
  }
}
