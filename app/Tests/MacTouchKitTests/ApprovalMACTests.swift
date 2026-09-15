import Foundation
import Testing
@testable import MacTouchKit

/// Pins the Swift side to docs/protocol-vectors.json. The firmware must
/// produce the same bytes; a mismatch here means the two have drifted.
@Suite struct ApprovalMACVectors {
  struct Vectors: Decodable {
    let device_key: String
    let nonce: String
    let slot: Int
    let material: String
    let mac: String
  }

  static func load() throws -> Vectors {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("docs/protocol-vectors.json")
    return try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))
  }

  @Test func materialMatchesVector() throws {
    let v = try Self.load()
    #expect(ApprovalMAC.material(nonce: v.nonce, slot: v.slot) == v.material)
  }

  @Test func computeMatchesVector() throws {
    let v = try Self.load()
    let key = try #require(Data(hex: v.device_key))
    #expect(ApprovalMAC.compute(key: key, nonce: v.nonce, slot: v.slot) == v.mac)
  }

  @Test func verifyAcceptsVectorAndRejectsChanges() throws {
    let v = try Self.load()
    let key = try #require(Data(hex: v.device_key))
    #expect(ApprovalMAC.verify(key: key, nonce: v.nonce, slot: v.slot, mac: v.mac))
    #expect(ApprovalMAC.verify(key: key, nonce: v.nonce.uppercased(), slot: v.slot, mac: v.mac))
    #expect(!ApprovalMAC.verify(key: key, nonce: v.nonce, slot: v.slot + 1, mac: v.mac))
    #expect(!ApprovalMAC.verify(key: key, nonce: v.nonce, slot: v.slot, mac: String(v.mac.dropLast()) + "0"))
    #expect(!ApprovalMAC.verify(key: key, nonce: v.nonce, slot: v.slot, mac: "zz"))
  }
}

@Suite struct HexDecoding {
  @Test func roundTrips() {
    #expect(Data(hex: "00ff7A") == Data([0x00, 0xff, 0x7a]))
    #expect(Data(hex: "") == Data())
    #expect(Data(hex: "abc") == nil)
    #expect(Data(hex: "0g") == nil)
  }
}
