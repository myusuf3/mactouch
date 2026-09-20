import Foundation
import MacTouchKit
import Testing
import MacTouchModel

/// Requests a fake daemon received, safe to append from the socket queue.
private final class Received: @unchecked Sendable {
  private let lock = NSLock()
  private var lines: [String] = []
  func append(_ line: String) { lock.lock(); lines.append(line); lock.unlock() }
  var all: [String] { lock.lock(); defer { lock.unlock() }; return lines }
}

@MainActor
private func waitUntil(_ condition: @escaping () -> Bool) async throws {
  let deadline = Date().addingTimeInterval(5)
  while !condition() {
    try #require(Date() < deadline, "condition not met in time")
    try await Task.sleep(nanoseconds: 20_000_000)
  }
}

@Suite struct DaemonModels {
  @Test @MainActor func mirrorsStatusSendsActionsAndNoticesTheDaemonGoing() async throws {
    let received = Received()
    let server = ControlServer(path: NSTemporaryDirectory() + "mactouch-model-\(UUID().uuidString.prefix(8)).sock")
    server.handler = { request, connection in
      switch request.verb {
      case "events":
        connection.subscribed = true
        connection.send(ControlLine.evt("device", [("state", "connected")]))
      case "status":
        connection.send(ControlLine.ok("status", [
          ("device", "connected"), ("ring", "breathe:red"), ("layers", "idle,privacy,notify"),
          ("monitors", "lock,mic"), ("sensor", "ready"), ("prints", "2"), ("idle", "cyan"),
        ]))
      default:
        received.append(request.line)
        connection.send(ControlLine.ok(request.verb))
      }
    }
    try server.start()

    let model = DaemonModel(path: server.path)
    try await waitUntil { model.daemonRunning && model.prints == 2 }
    #expect(model.deviceConnected)
    #expect(model.sensor == "ready")
    #expect(model.ring == "breathe:red")
    #expect(model.layers == ["idle", "privacy", "notify"])
    #expect(model.notifyActive)
    #expect(model.idle == .cyan)
    #expect(model.monitors == [.lock, .mic])

    model.setIdle(.red)
    model.setMonitor(.camera, enabled: true)
    model.clearNotify()
    try await waitUntil { received.all.count == 3 }
    #expect(received.all == ["idle red", "monitor camera on", "clear"])

    server.stop()
    try await waitUntil { !model.daemonRunning }
  }
}
