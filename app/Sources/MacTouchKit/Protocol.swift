import Foundation

/// The eight states the ring can show. Raw values are the wire names.
public enum LEDColour: String, CaseIterable, Sendable {
  case off, blue, green, cyan, red, magenta, yellow, white
}

public enum LEDMode: String, CaseIterable, Sendable {
  case off, on, breathe, flash, fadein, fadeout
}

public enum TouchSource: String, CaseIterable, Sendable {
  case pin, poll
}

/// A command for the device. `line` is the exact text sent, without the newline.
public enum Command: Equatable, Sendable {
  case ping
  case status
  case led(LEDMode, LEDColour, LEDColour? = nil, cycles: Int = 0)
  case idle(LEDColour)
  case identify(timeoutMs: Int, prompt: LEDColour? = nil, nonce: String? = nil)
  case enroll(slot: Int)
  case delete(slot: Int)
  case deleteAll
  case slots
  case watch(Bool)
  case touch(TouchSource)
  case pair(timeoutMs: Int = 30000)
  /// `STATUS`, `GENKEY` or `RESET`; the last two wait for a finger.
  case piv(String)
  case gpio
  case selftest
  case cancel
  case reboot
  case bootloader

  public var verb: String {
    switch self {
    case .ping: return "PING"
    case .status: return "STATUS"
    case .led: return "LED"
    case .idle: return "IDLE"
    case .identify: return "IDENTIFY"
    case .enroll: return "ENROLL"
    case .delete, .deleteAll: return "DELETE"
    case .slots: return "SLOTS"
    case .watch: return "WATCH"
    case .touch: return "TOUCH"
    case .pair: return "PAIR"
    case .piv: return "PIV"
    case .gpio: return "GPIO"
    case .selftest: return "SELFTEST"
    case .cancel: return "CANCEL"
    case .reboot: return "REBOOT"
    case .bootloader: return "BOOTLOADER"
    }
  }

  /// The verb the device answers with. PING is acknowledged as PONG.
  public var responseVerb: String { self == .ping ? "PONG" : verb }

  public var line: String {
    switch self {
    case .led(let mode, let colour, let colour2, let cycles):
      if mode == .off { return "LED off" }
      var parts = ["LED", mode.rawValue, colour.rawValue]
      if let colour2, colour2 != colour { parts.append(colour2.rawValue) }
      if cycles > 0 { parts.append(String(cycles)) }
      return parts.joined(separator: " ")
    case .idle(let colour):
      return "IDLE \(colour.rawValue)"
    case .identify(let timeoutMs, let prompt, let nonce):
      var parts = ["IDENTIFY", "timeout=\(timeoutMs)"]
      if let prompt { parts.append("prompt=\(prompt.rawValue)") }
      if let nonce { parts.append("nonce=\(nonce)") }
      return parts.joined(separator: " ")
    case .enroll(let slot): return "ENROLL slot=\(slot)"
    case .delete(let slot): return "DELETE slot=\(slot)"
    case .deleteAll: return "DELETE all"
    case .watch(let on): return "WATCH \(on ? "on" : "off")"
    case .touch(let source): return "TOUCH \(source.rawValue)"
    case .pair(let timeoutMs): return "PAIR timeout=\(timeoutMs)"
    case .piv(let sub): return "PIV \(sub)"
    default: return verb
    }
  }
}

/// `key=value` fields from a response or event line.
public struct Fields: Equatable, Sendable {
  public var values: [String: String]
  public var positional: [String]

  public init(values: [String: String] = [:], positional: [String] = []) {
    self.values = values
    self.positional = positional
  }

  public subscript(_ key: String) -> String? { values[key] }
  public func int(_ key: String) -> Int? { values[key].flatMap(Int.init) }
  public func bool(_ key: String) -> Bool? {
    switch values[key] {
    case "1", "on", "true": return true
    case "0", "off", "false": return false
    default: return nil
    }
  }
}

/// One line from the device.
public enum DeviceLine: Equatable, Sendable {
  case ok(verb: String, fields: Fields)
  case err(verb: String, reason: String)
  case event(name: String, fields: Fields)

  public static func parse(_ raw: String) -> DeviceLine? {
    guard let tagged = TaggedLine.parse(raw, ok: "OK", err: "ERR", evt: "EVT") else { return nil }
    switch tagged {
    case .ok(let verb, let fields): return .ok(verb: verb, fields: fields)
    case .err(let verb, let reason): return .err(verb: verb, reason: reason)
    case .evt(let name, let fields): return .event(name: name, fields: fields)
    }
  }
}

/// Accumulates bytes and yields complete lines. `\r` is dropped.
public struct LineBuffer {
  private var buffer = Data()
  public private(set) var droppedOverlong = 0
  public let limit: Int

  public init(limit: Int = 1024) { self.limit = limit }

  public mutating func append(_ data: Data) -> [String] {
    buffer.append(data)
    var lines: [String] = []
    while let newline = buffer.firstIndex(of: 0x0a) {
      let chunk = buffer[buffer.startIndex..<newline]
      buffer.removeSubrange(buffer.startIndex...newline)
      if chunk.count > limit { droppedOverlong += 1; continue }
      if let text = String(data: chunk.filter { $0 != 0x0d }, encoding: .utf8), !text.isEmpty {
        lines.append(text)
      }
    }
    if buffer.count > limit {
      buffer.removeAll()
      droppedOverlong += 1
    }
    return lines
  }
}
