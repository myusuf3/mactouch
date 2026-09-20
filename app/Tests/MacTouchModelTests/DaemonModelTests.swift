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

/// A daemon with a connected device, two fingers and a notify layer, that
/// records every other request and answers `ok`.
private func fakeDaemon(recording received: Received) throws -> ControlServer {
  let server = ControlServer(path: NSTemporaryDirectory() + "mactouch-model-\(UUID().uuidString.prefix(8)).sock")
  server.handler = { request, connection in
    switch request.verb {
    case "events":
      connection.subscribed = true
      connection.send(ControlLine.evt("device", [("state", "connected")]))
    case "status":
      connection.send(ControlLine.ok("status", [
        ("device", "connected"), ("ring", "breathe:red"), ("layers", "idle,privacy,notify"),
        ("monitors", "lock,mic"), ("sensor", "ready"), ("prints", "2"), ("idle", "cyan"), ("fw", "0.1.1"),
      ]))
    case "slots":
      connection.send(ControlLine.ok("slots", [("used", "1,3"), ("capacity", "20")]))
    case "enroll":
      received.append(request.line)
      for step in ["touch", "lift", "touch_again", "processing"] {
        connection.send(ControlLine.evt("enroll", [("step", step)]))
      }
      connection.send(ControlLine.ok("enroll", [("slot", request["slot"] ?? "?")]))
    case "selftest":
      connection.send(ControlLine.ok("selftest"))
    default:
      received.append(request.line)
      connection.send(ControlLine.ok(request.verb))
    }
  }
  try server.start()
  return server
}

@Suite struct DaemonModels {
  @Test @MainActor func mirrorsStatusSendsActionsAndNoticesTheDaemonGoing() async throws {
    let received = Received()
    let server = try fakeDaemon(recording: received)
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

  @Test @MainActor func enrolsIntoTheFirstFreeSlotAndDeletes() async throws {
    let received = Received()
    let server = try fakeDaemon(recording: received)
    defer { server.stop() }
    let suite = "mactouch-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    let model = DaemonModel(path: server.path, defaults: defaults)
    try await waitUntil { model.daemonRunning }
    model.refreshSlots()
    try await waitUntil { model.slots == [1, 3] }
    #expect(model.firstFreeSlot == 2)

    model.enrol()
    #expect(model.enrolment == .running(step: nil))
    try await waitUntil { model.enrolment == .done(slot: 2) }
    #expect(received.all == ["enroll slot=2"])

    model.rename(1, to: "Thumb")
    #expect(model.names[1] == "Thumb")
    #expect(DaemonModel(path: server.path, defaults: defaults).names[1] == "Thumb")

    model.delete(slot: 1)
    try await waitUntil { received.all.count == 2 }
    #expect(received.all.last == "delete slot=1")
    #expect(model.names[1] == nil)
  }

  @Test @MainActor func reportsHealthFromTheDaemon() async throws {
    let server = try fakeDaemon(recording: Received())
    defer { server.stop() }
    let model = DaemonModel(path: server.path)
    model.refreshHealth()
    try await waitUntil { model.health != nil }
    let rows = Dictionary(uniqueKeysWithValues: (model.health?.checks ?? []).map { ($0.name, $0.verdict) })
    #expect(rows["daemon"] == .ok)
    #expect(rows["signature"] == .ok)
    #expect(rows["fingers"] == .ok)
  }
}
