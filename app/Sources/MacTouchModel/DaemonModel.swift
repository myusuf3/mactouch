import Foundation
import MacTouchKit

/// What the app shows, fed by mactouchd's event stream. One connection stays
/// subscribed to `events` for the life of the app, announces the app as the
/// UI that shows requests, and reconnects when it drops; requests run one at a time on `requests`, each on a short-lived
/// connection, so the stream never waits on the device and the main queue
/// never waits on the socket. Published properties change on the main queue.
public final class DaemonModel: ObservableObject {
  public enum Enrolment: Equatable {
    case idle
    /// `step` is the daemon's `touch`, `lift`, `touch_again` or `processing`,
    /// nil until the first one arrives.
    case running(step: String?)
    case done(slot: Int)
    case failed(String)
  }

  /// A fingerprint request in flight on the daemon.
  public struct Request: Equatable {
    /// `plain` for an ordinary identify, `nonce` for one carrying a nonce,
    /// which is how PAM asks; the ring is blue or white to match.
    public let kind: String
    public let reason: String
    public init(kind: String, reason: String) { self.kind = kind; self.reason = reason }
  }

  @Published public private(set) var daemonRunning = false
  @Published public private(set) var deviceConnected = false
  @Published public private(set) var sensor: String?
  @Published public private(set) var prints: Int?
  /// The ring as the daemon spells it, `mode:colour[:colour2]`.
  @Published public private(set) var ring: String?
  /// Active policy layers, lowest first; the last one owns the ring.
  @Published public private(set) var layers: [String] = []
  @Published public private(set) var idle: LEDColour?
  @Published public private(set) var monitors: Set<MonitorName> = []

  @Published public private(set) var slots: [Int] = []
  @Published public private(set) var capacity = 20
  @Published public private(set) var enrolment: Enrolment = .idle
  /// Names people give their fingers, kept in the app's defaults; the
  /// device knows only slot numbers.
  @Published public private(set) var names: [Int: String]
  @Published public private(set) var health: HealthReport?
  @Published public private(set) var request: Request?
  /// Failed attempts during the current request, so the panel can say so.
  @Published public private(set) var noMatches = 0

  public var notifyActive: Bool { layers.contains("notify") }
  public var firstFreeSlot: Int? { (1...capacity).first { !slots.contains($0) } }

  private let path: String
  private let defaults: UserDefaults
  private static let namesKey = "slotNames"
  private let requests = DispatchQueue(label: "mactouch.requests")

  public init(path: String = ControlSocketPath.default, defaults: UserDefaults = .standard) {
    self.path = path
    self.defaults = defaults
    let stored = defaults.dictionary(forKey: Self.namesKey) as? [String: String] ?? [:]
    names = Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in Int(key).map { ($0, value) } })
    let thread = Thread { [weak self] in self?.streamEvents() }
    thread.name = "mactouch.events"
    thread.start()
  }

  // MARK: actions

  public func setIdle(_ colour: LEDColour) {
    send(ControlRequest(verb: "idle", positional: [colour.rawValue]))
  }

  public func setMonitor(_ name: MonitorName, enabled: Bool) {
    send(ControlRequest(verb: "monitor", positional: [name.rawValue, enabled ? "on" : "off"]))
  }

  public func clearNotify() {
    send(ControlRequest(verb: "clear"))
  }

  // MARK: fingers

  public func refreshSlots() {
    requests.async { [weak self] in self?.loadSlots() }
  }

  /// Enrols into the first free slot. The daemon streams the steps on the
  /// request's own connection, so they arrive here and nowhere else.
  public func enrol() {
    if case .running = enrolment { return }
    guard let slot = firstFreeSlot else { return }
    enrolment = .running(step: nil)
    requests.async { [weak self] in
      guard let self else { return }
      do {
        let client = try ControlClient(path: path)
        defer { client.close() }
        _ = try client.request(ControlRequest(verb: "enroll", values: ["slot": "\(slot)"]), timeout: 55) { name, fields in
          guard name == "enroll" else { return }
          self.publish { $0.enrolment = .running(step: fields["step"]) }
        }
        publish { $0.enrolment = .done(slot: slot) }
      } catch {
        let reason = describe(error)
        publish { $0.enrolment = .failed(reason) }
      }
      loadSlots()
      refreshStatus()
    }
  }

  public func delete(slot: Int) {
    send(ControlRequest(verb: "delete", values: ["slot": "\(slot)"]))
    requests.async { [weak self] in self?.loadSlots() }
    rename(slot, to: "")
  }

  public func rename(_ slot: Int, to name: String) {
    names[slot] = name.isEmpty ? nil : name
    defaults.set(Dictionary(uniqueKeysWithValues: names.map { ("\($0.key)", $0.value) }), forKey: Self.namesKey)
  }

  private func loadSlots() {
    guard let client = try? ControlClient(path: path) else { return }
    defer { client.close() }
    guard let reply = try? client.request(ControlRequest(verb: "slots")) else { return }
    let used = reply["used"]?.split(separator: ",").compactMap { Int($0) } ?? []
    let capacity = reply.int("capacity")
    publish { model in
      model.slots = used
      if let capacity { model.capacity = capacity }
    }
  }

  // MARK: diagnostics

  /// The same check-up as `mactouch doctor`, including the firmware
  /// self-test, so it takes a device round trip.
  public func refreshHealth() {
    requests.async { [weak self] in
      guard let self else { return }
      let report = HealthReport.viaDaemon(at: path)
      publish { $0.health = report }
    }
  }

  // MARK: requests

  public func cancel() {
    send(ControlRequest(verb: "cancel"))
  }

  // MARK: daemon

  /// Loads the launch agent install.sh wrote; the event stream picks the
  /// daemon up on its next retry.
  public func startDaemon() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = ["bootstrap", "gui/\(getuid())", NSHomeDirectory() + "/Library/LaunchAgents/dev.mactouch.daemon.plist"]
    try? process.run()
  }

  /// One request off the main queue, then a status refresh so the menu shows
  /// what the daemon did rather than what was asked. A menu has nowhere to
  /// put an error; a rejected request simply leaves the state as it was.
  private func send(_ request: ControlRequest) {
    requests.async { [weak self] in
      guard let self else { return }
      if let client = try? ControlClient(path: path) {
        defer { client.close() }
        _ = try? client.request(request)
      }
      refreshStatus()
    }
  }

  // MARK: events

  private func streamEvents() {
    while true {
      do {
        let client = try ControlClient(path: path)
        defer { client.close() }
        try client.send("events")
        // This app shows requests itself, so the daemon's popup stays quiet
        // while this connection lives. Said again on every reconnect.
        try client.send("hello ui=1")
        refreshStatus()
        while true {
          guard let line = try client.readLine(timeout: 60) else { continue }
          if case .evt(let name, let fields)? = ControlLine.parse(line) { handle(name, fields) }
        }
      } catch {
        publish { $0.daemonRunning = false }
      }
      Thread.sleep(forTimeInterval: 2)
    }
  }

  private func handle(_ name: String, _ fields: Fields) {
    switch name {
    case "device":
      publish { $0.deviceConnected = fields["state"] == "connected" }
      refreshStatus()
    case "ring":
      publish { $0.ring = fields["state"] }
      refreshStatus()
    case "request":
      let pending = fields["state"] == "pending"
      let request = pending ? Request(kind: fields["kind"] ?? "plain", reason: fields["reason"] ?? "") : nil
      publish { model in
        model.request = request
        model.noMatches = 0
      }
    case "nomatch":
      publish { $0.noMatches += 1 }
    default:
      break
    }
  }

  /// Sensor and finger count only come from `status`, and the daemon omits
  /// them while a long command owns the device, so a reply without them
  /// keeps the last known values.
  private func refreshStatus() {
    guard let client = try? ControlClient(path: path) else { return }
    defer { client.close() }
    guard let status = try? client.request(ControlRequest(verb: "status")) else { return }
    publish { model in
      model.daemonRunning = true
      model.deviceConnected = status["device"] == "connected"
      model.ring = status["ring"]
      model.layers = status["layers"]?.split(separator: ",").map(String.init) ?? []
      model.idle = status["idle"].flatMap(LEDColour.init)
      model.monitors = Set(status["monitors"]?.split(separator: ",").compactMap { MonitorName(rawValue: String($0)) } ?? [])
      if !model.deviceConnected {
        model.sensor = nil
        model.prints = nil
      }
      if let sensor = status["sensor"] { model.sensor = sensor }
      if let prints = status.int("prints") { model.prints = prints }
    }
  }

  private func publish(_ change: @escaping (DaemonModel) -> Void) {
    DispatchQueue.main.async { change(self) }
  }

  private func describe(_ error: Error) -> String {
    if case ControlError.rejected(_, let reason) = error { return reason }
    return "\(error)"
  }
}
