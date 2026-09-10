import Foundation

/// A request on the control socket: lower-case verb, positional words, and
/// `key=value` fields. `reason=` runs to the end of the line and may contain
/// spaces, so it is always the last field.
public struct ControlRequest: Equatable, Sendable {
  public var verb: String
  public var positional: [String]
  public var values: [String: String]

  public init(verb: String, positional: [String] = [], values: [String: String] = [:]) {
    self.verb = verb
    self.positional = positional
    self.values = values
  }

  public subscript(_ key: String) -> String? { values[key] }
  public func int(_ key: String) -> Int? { values[key].flatMap(Int.init) }
  public func double(_ key: String) -> Double? { values[key].flatMap(Double.init) }

  public static func parse(_ raw: String) -> ControlRequest? {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    var reason: String?
    if let range = text.range(of: "reason=") {
      reason = String(text[range.upperBound...])
      text = String(text[..<range.lowerBound])
    }
    var tokens = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    guard !tokens.isEmpty else { return nil }
    var request = ControlRequest(verb: tokens.removeFirst().lowercased())
    for token in tokens {
      if let eq = token.firstIndex(of: "=") {
        request.values[String(token[..<eq])] = String(token[token.index(after: eq)...])
      } else {
        request.positional.append(token)
      }
    }
    if let reason, !reason.isEmpty { request.values["reason"] = reason }
    return request
  }

  public var line: String {
    var parts = [verb] + positional
    for key in values.keys.sorted() where key != "reason" {
      parts.append("\(key)=\(values[key]!)")
    }
    if let reason = values["reason"] { parts.append("reason=\(reason)") }
    return parts.joined(separator: " ")
  }
}

/// A line from the daemon to a client.
public enum ControlLine: Equatable, Sendable {
  case ok(verb: String, fields: Fields)
  case err(verb: String, reason: String)
  case evt(name: String, fields: Fields)

  public static func parse(_ raw: String) -> ControlLine? {
    guard let tagged = TaggedLine.parse(raw, ok: "ok", err: "err", evt: "evt") else { return nil }
    switch tagged {
    case .ok(let verb, let fields): return .ok(verb: verb, fields: fields)
    case .err(let verb, let reason): return .err(verb: verb, reason: reason)
    case .evt(let name, let fields): return .evt(name: name, fields: fields)
    }
  }

  public static func ok(_ verb: String, _ fields: [(String, String)] = []) -> String {
    (["ok", verb] + fields.map { "\($0)=\($1)" }).joined(separator: " ")
  }
  public static func err(_ verb: String, _ reason: String) -> String { "err \(verb) reason=\(reason)" }
  public static func evt(_ name: String, _ fields: [(String, String)] = []) -> String {
    (["evt", name] + fields.map { "\($0)=\($1)" }).joined(separator: " ")
  }
  /// Re-emits a device event on the socket in the socket's spelling.
  public static func evt(_ name: String, _ fields: Fields) -> String {
    evt(name, fields.values.keys.sorted().map { ($0, fields.values[$0]!) })
  }
}

/// Shared shape of both protocols: a tag, a verb, then fields; an error's
/// reason runs to the end of the line.
enum TaggedLine {
  case ok(String, Fields)
  case err(String, String)
  case evt(String, Fields)

  static func parse(_ raw: String, ok: String, err: String, evt: String) -> TaggedLine? {
    let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    var tokens = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    guard tokens.count >= 2 else { return nil }
    let tag = tokens.removeFirst()
    let verb = tokens.removeFirst()
    switch tag {
    case ok: return .ok(verb, fields(tokens))
    case evt: return .evt(verb, fields(tokens))
    case err:
      if let range = line.range(of: "reason=") { return .err(verb, String(line[range.upperBound...])) }
      return .err(verb, tokens.joined(separator: " "))
    default: return nil
    }
  }

  static func fields(_ tokens: [String]) -> Fields {
    var result = Fields()
    for token in tokens {
      if let eq = token.firstIndex(of: "=") {
        result.values[String(token[..<eq])] = String(token[token.index(after: eq)...])
      } else {
        result.positional.append(token)
      }
    }
    return result
  }
}

public enum ControlSocketPath {
  /// `~/Library/Application Support/MacTouch/control.sock`, for the given
  /// home directory so root-run code (PAM) can address a user's daemon.
  public static func forHome(_ home: String) -> String {
    home + "/Library/Application Support/MacTouch/control.sock"
  }
  public static var `default`: String { forHome(NSHomeDirectory()) }
}
