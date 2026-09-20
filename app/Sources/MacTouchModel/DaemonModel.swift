import Foundation
import MacTouchKit

/// What the menu shows, fed by mactouchd's event stream. One connection stays
/// subscribed to `events` for the life of the app and reconnects when it
/// drops; `status` runs on a short-lived second connection so the stream
/// never waits on the device. Published properties change on the main queue.
public final class DaemonModel: ObservableObject {
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

  public var notifyActive: Bool { layers.contains("notify") }

  private let path: String
  private let requests = DispatchQueue(label: "mactouch.requests")

  public init(path: String = ControlSocketPath.default) {
    self.path = path
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
}
