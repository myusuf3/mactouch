import CryptoKit
import Foundation

/// A mactouch app image as the build writes it (`firmware/build/mactouch.bin`).
public struct FirmwareImage: Sendable {
  public let data: Data
  public let sha256: String
  /// From the image's app description, as `MACTOUCH_VERSION` set it.
  public let version: String?
  public let project: String?

  public init(data: Data) {
    self.data = data
    sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    // ESP-IDF places esp_app_desc_t right after the image header and the
    // first segment header: magic at 0x20, version at 0x30, project at 0x50.
    let magic: [UInt8] = [0x32, 0x54, 0xCD, 0xAB]
    if data.count >= 0x70, Array(data[0x20..<0x24]) == magic {
      version = Self.string(data[0x30..<0x50])
      project = Self.string(data[0x50..<0x70])
    } else {
      version = nil
      project = nil
    }
  }

  public init(contentsOf url: URL) throws {
    self.init(data: try Data(contentsOf: url))
  }

  /// An ESP-IDF app image starts with 0xE9, and ours names itself mactouch.
  public var isMactouch: Bool { data.first == 0xE9 && project == "mactouch" }

  private static func string(_ bytes: Data) -> String? {
    let text = String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    return text.isEmpty ? nil : text
  }
}

/// Compares dotted versions numerically, so 0.10.0 is newer than 0.9.3.
public func firmwareVersion(_ a: String, isOlderThan b: String) -> Bool {
  let left = a.split(separator: ".").map { Int($0) ?? 0 }
  let right = b.split(separator: ".").map { Int($0) ?? 0 }
  for i in 0..<max(left.count, right.count) {
    let x = i < left.count ? left[i] : 0, y = i < right.count ? right[i] : 0
    if x != y { return x < y }
  }
  return false
}

/// Drives an update over the link, through the daemon or the serial port;
/// `send` is one request and its reply. The device restarts into the new
/// image after the last step.
public struct FirmwareUpdater {
  /// 168 bytes is 224 base64 characters, which keeps a WRITE line inside
  /// the protocol's 256-byte limit with room for the offset.
  public static let chunk = 168

  public enum Step: Equatable, Sendable {
    case waitingForTouch
    case writing(done: Int, total: Int)
    case installing
  }

  public let image: FirmwareImage
  public let send: (_ step: String, _ timeout: TimeInterval) throws -> Fields

  public init(image: FirmwareImage, send: @escaping (_ step: String, _ timeout: TimeInterval) throws -> Fields) {
    self.image = image
    self.send = send
  }

  public func run(progress: (Step) -> Void = { _ in }) throws {
    progress(.waitingForTouch)
    _ = try send("BEGIN size=\(image.data.count) sha256=\(image.sha256)", 50)
    var offset = 0
    do {
      while offset < image.data.count {
        let end = min(offset + Self.chunk, image.data.count)
        let encoded = image.data[offset..<end].base64EncodedString()
        let reply = try send("WRITE off=\(offset) data=\(encoded)", 10)
        guard reply.int("next") == end else { throw FirmwareError.outOfStep(expected: end, got: reply.int("next")) }
        offset = end
        progress(.writing(done: offset, total: image.data.count))
      }
      progress(.installing)
    } catch {
      _ = try? send("ABORT", 5)
      throw error
    }
    // The device restarts as soon as it accepts the image, so the reply can
    // be lost with the port: directly as a disconnect, or through the
    // daemon as `reason=device`. Either is expected; the caller confirms the
    // version once the board is back.
    do {
      _ = try send("END", 20)
    } catch ControlError.disconnected {
    } catch DeviceError.disconnected {
    } catch ControlError.rejected(_, let reason) where reason == "device" {
    }
  }
}

extension ControlRequest {
  /// An updater step as the daemon's `fw` verb: `WRITE off=0 data=…` becomes
  /// `fw write off=0 data=…`.
  public static func firmware(_ step: String) -> ControlRequest {
    let words = step.split(separator: " ").map(String.init)
    var request = ControlRequest(verb: "fw", positional: [words[0].lowercased()])
    for word in words.dropFirst() {
      guard let eq = word.firstIndex(of: "=") else { continue }
      request.values[String(word[..<eq])] = String(word[word.index(after: eq)...])
    }
    return request
  }
}

/// How an update ended, judged from the board once it is back.
public enum FirmwareOutcome: Equatable, Sendable {
  case confirmed(version: String, slot: String)
  case rolledBack(to: String?)
  case notBack
  case stillOnProbation
}

extension FirmwareUpdater {
  /// Waits for the board to come back and settle. A new image is on
  /// probation until it has run healthily for a while, and a crash in that
  /// time rolls the board back, so only the end of probation says the
  /// update took; seeing the new version once does not. `status` returns
  /// the board's status, or nil while it is away or has not answered yet.
  public static func awaitOutcome(for image: FirmwareImage, status: () -> Fields?,
                                  onProbation: () -> Void = {}, timeout: TimeInterval = 90) -> FirmwareOutcome {
    let deadline = Date().addingTimeInterval(timeout)
    var seenAtAll = false
    var toldProbation = false
    Thread.sleep(forTimeInterval: 2)
    while Date() < deadline {
      guard let back = status(), let version = back["fw"] else {
        Thread.sleep(forTimeInterval: 1)
        continue
      }
      seenAtAll = true
      if version != image.version { return .rolledBack(to: version) }
      if back["probation"] != "yes" { return .confirmed(version: version, slot: back["slot"] ?? "?") }
      if !toldProbation { onProbation(); toldProbation = true }
      Thread.sleep(forTimeInterval: 2)
    }
    return seenAtAll ? .stillOnProbation : .notBack
  }
}

public enum FirmwareError: Error, CustomStringConvertible {
  case notMactouch
  case outOfStep(expected: Int, got: Int?)

  public var description: String {
    switch self {
    case .notMactouch: return "not a mactouch firmware image"
    case .outOfStep(let expected, let got): return "device lost step: expected \(expected), got \(got.map(String.init) ?? "nothing")"
    }
  }
}
