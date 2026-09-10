import Foundation

/// What the ring should show.
public struct RingState: Equatable, Sendable, CustomStringConvertible {
  public var mode: LEDMode
  public var colour: LEDColour
  public var colour2: LEDColour

  public init(_ mode: LEDMode, _ colour: LEDColour, _ colour2: LEDColour? = nil) {
    if mode == .off || colour == .off {
      self.mode = .off; self.colour = .off; self.colour2 = .off
    } else {
      self.mode = mode; self.colour = colour; self.colour2 = colour2 ?? colour
    }
  }

  public static let off = RingState(.off, .off)
  public static func steady(_ colour: LEDColour) -> RingState { RingState(colour == .off ? .off : .on, colour) }

  public var command: Command { .led(mode, colour, colour2 == colour ? nil : colour2) }
  public var description: String {
    colour2 == colour ? "\(mode.rawValue):\(colour.rawValue)" : "\(mode.rawValue):\(colour.rawValue):\(colour2.rawValue)"
  }
}

/// The layers of the policy stack, lowest priority first. The highest active
/// layer owns the ring; when it clears, the next one shows through.
public enum RingLayer: Int, CaseIterable, Comparable, Sendable {
  case idle = 0
  case locked = 10
  case focus = 20
  case privacy = 30
  case notify = 40
  case prompt = 50

  public static func < (a: RingLayer, b: RingLayer) -> Bool { a.rawValue < b.rawValue }
  public var name: String {
    switch self {
    case .idle: return "idle"
    case .locked: return "locked"
    case .focus: return "focus"
    case .privacy: return "privacy"
    case .notify: return "notify"
    case .prompt: return "prompt"
    }
  }
}

/// Pure resolver: layers in, one ring state out. Not thread-safe; the daemon
/// drives it from one queue.
public struct LEDPolicy {
  public struct Entry: Equatable { public var state: RingState; public var expires: Date? }

  public var idle: LEDColour
  private var layers: [RingLayer: Entry] = [:]

  public init(idle: LEDColour = .blue) { self.idle = idle }

  public mutating func set(_ layer: RingLayer, _ state: RingState, for duration: TimeInterval? = nil, now: Date = Date()) {
    precondition(layer != .idle, "set idle through the idle property")
    layers[layer] = Entry(state: state, expires: duration.map { now.addingTimeInterval($0) })
  }

  public mutating func clear(_ layer: RingLayer) { layers.removeValue(forKey: layer) }

  public mutating func dropExpired(now: Date = Date()) {
    layers = layers.filter { $0.value.expires.map { $0 > now } ?? true }
  }

  public func resolve(now: Date = Date()) -> RingState {
    let live = layers.filter { $0.value.expires.map { $0 > now } ?? true }
    if let top = live.keys.max() { return live[top]!.state }
    return .steady(idle)
  }

  public func active(now: Date = Date()) -> [RingLayer] {
    [.idle] + layers.filter { $0.value.expires.map { $0 > now } ?? true }.keys.sorted()
  }

  /// When the resolved state will next change on its own, if ever.
  public func nextExpiry(now: Date = Date()) -> Date? {
    layers.values.compactMap(\.expires).filter { $0 > now }.min()
  }
}
