import Foundation
import MacTouchKit

/// What the menu shows, fed by mactouchd's event stream. One connection stays
/// subscribed to `events` for the life of the app and reconnects when it
/// drops; `status` runs on a short-lived second connection so the stream
/// never waits on the device. Published properties change on the main queue.
final class DaemonModel: ObservableObject {
  @Published private(set) var daemonRunning = false
  @Published private(set) var deviceConnected = false
  @Published private(set) var sensor: String?
  @Published private(set) var prints: Int?
  /// The ring as the daemon spells it, `mode:colour[:colour2]`.
  @Published private(set) var ring: String?
  /// Active policy layers, lowest first; the last one owns the ring.
  @Published private(set) var layers: [String] = []

  private let path: String

  init(path: String = ControlSocketPath.default) {
    self.path = path
    let thread = Thread { [weak self] in self?.streamEvents() }
    thread.name = "mactouch.events"
    thread.start()
  }

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
