import Foundation
import MacTouchKit
import Testing
import MacTouchModel

/// Requests a fake daemon received, safe to append from the socket queue.
/// The automatic `hello ui=1` is counted apart so tests can compare the rest.
private final class Received: @unchecked Sendable {
  private let lock = NSLock()
  private var lines: [String] = []
  private var helloCount = 0
  func append(_ line: String) { lock.lock(); lines.append(line); lock.unlock() }
  func hello() { lock.lock(); helloCount += 1; lock.unlock() }
  var all: [String] { lock.lock(); defer { lock.unlock() }; return lines }
  var hellos: Int { lock.lock(); defer { lock.unlock() }; return helloCount }
}

@MainActor
private func waitUntil(seconds: TimeInterval = 5, _ condition: @escaping () -> Bool) async throws {
  let deadline = Date().addingTimeInterval(seconds)
  while !condition() {
    try #require(Date() < deadline, "condition not met in time")
    try await Task.sleep(nanoseconds: 20_000_000)
  }
}

/// A daemon with a connected device, two fingers and a notify layer, that
/// records every other request and answers `ok`.
private func fakeDaemon(recording received: Received, at path: String? = nil) throws -> ControlServer {
  let server = ControlServer(path: path ?? NSTemporaryDirectory() + "mactouch-model-\(UUID().uuidString.prefix(8)).sock")
  server.handler = { request, connection in
    switch request.verb {
    case "events":
      connection.subscribed = true
      connection.send(ControlLine.evt("device", [("state", "connected")]))
    case "status":
      connection.send(ControlLine.ok("status", [
        ("device", "connected"), ("ring", "breathe:red"), ("layers", "idle,privacy,notify"),
        ("monitors", "lock,mic"), ("sensor", "ready"), ("prints", "2"), ("idle", "cyan"), ("fw", "0.1.1"),
        ("focus", "menubar"),
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
    case "piv":
      if request.positional == ["status"] {
        connection.send(ControlLine.ok("piv", [("enabled", "yes"), ("identity", "no"), ("pin", "default"), ("retries", "3"), ("flash", "encrypted")]))
      } else {
        received.append(request.line)
        connection.send(ControlLine.ok("piv"))
      }
    case "hello":
      received.hello()
      connection.send(ControlLine.ok("hello", [("proto", "1")]))
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
    #expect(model.ringState == RingState(.breathe, .red))
    #expect(model.focusSource == .menubar)
    #expect(model.layers == ["idle", "privacy", "notify"])
    #expect(model.notifyActive)
    #expect(model.idle == .cyan)
    #expect(model.monitors == [.lock, .mic])
    #expect(model.idleCoveredNote == "A notification is showing, so the ring shows red until it ends.")

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

  @Test @MainActor func announcesItselfFollowsRequestsAndCancels() async throws {
    let received = Received()
    var server = try fakeDaemon(recording: received)
    let model = DaemonModel(path: server.path)
    try await waitUntil { received.hellos == 1 }
    try await waitUntil { model.daemonRunning }

    server.broadcast(ControlLine.evt("request", [("state", "pending"), ("kind", "nonce"), ("reason", "deploy to prod")]))
    try await waitUntil { model.request != nil }
    #expect(model.request == DaemonModel.Request(kind: "nonce", reason: "deploy to prod"))
    server.broadcast(ControlLine.evt("nomatch"))
    try await waitUntil { model.noMatches == 1 }
    model.cancel()
    try await waitUntil { received.all.last == "cancel" }
    server.broadcast(ControlLine.evt("request", [("state", "done"), ("kind", "nonce")]))
    try await waitUntil { model.request == nil }
    #expect(model.noMatches == 0)

    // A daemon restart must hear hello again without being asked.
    let path = server.path
    server.stop()
    try await waitUntil { !model.daemonRunning }
    server = try fakeDaemon(recording: received, at: path)
    defer { server.stop() }
    try await waitUntil { received.hellos == 2 }
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

  @Test @MainActor func readsTheSmartCardAndShowsItsTouchAsARequest() async throws {
    let received = Received()
    let server = try fakeDaemon(recording: received)
    defer { server.stop() }
    let model = DaemonModel(path: server.path)
    try await waitUntil { model.daemonRunning }
    model.refreshSmartCard()
    try await waitUntil { model.smartCard != nil }
    #expect(model.smartCard?.enabled == true)
    #expect(model.smartCard?.encrypted == true)
    #expect(model.smartCard?.pinIsDefault == true)
    #expect(model.smartCard?.identity == false)

    model.setSmartCard(enabled: false)
    try await waitUntil { received.all.contains("piv off") }

    server.broadcast(ControlLine.evt("piv", [("state", "pending")]))
    try await waitUntil { model.request?.kind == "piv" }
    server.broadcast(ControlLine.evt("piv", [("state", "done"), ("result", "match")]))
    try await waitUntil { model.request == nil }
  }

  @Test(.timeLimit(.minutes(1))) @MainActor func updatesFirmwareFromTheBundledImage() async throws {
    var bytes = [UInt8](repeating: 0, count: 400)
    bytes[0] = 0xE9
    bytes.replaceSubrange(0x20..<0x24, with: [0x32, 0x54, 0xCD, 0xAB])
    bytes.replaceSubrange(0x30..<0x35, with: Array("0.3.0".utf8))
    bytes.replaceSubrange(0x50..<0x58, with: Array("mactouch".utf8))
    let image = FirmwareImage(data: Data(bytes))

    let received = Received()
    let installed = Received()
    let server = ControlServer(path: NSTemporaryDirectory() + "mactouch-fw-\(UUID().uuidString.prefix(8)).sock")
    var written = 0
    server.handler = { request, connection in
      switch request.verb {
      case "events": connection.subscribed = true; connection.send(ControlLine.evt("device", [("state", "connected")]))
      case "hello": connection.send(ControlLine.ok("hello"))
      case "status":
        let version = installed.all.isEmpty ? "0.2.1" : "0.3.0"
        connection.send(ControlLine.ok("status", [("device", "connected"), ("fw", version), ("slot", "ota_1")]))
      case "fw":
        received.append(request.positional.first ?? "?")
        switch request.positional.first {
        case "write":
          written += Data(base64Encoded: request["data"] ?? "")?.count ?? 0
          connection.send(ControlLine.ok("fw", [("next", "\(written)")]))
        case "end":
          installed.append("yes")
          connection.send(ControlLine.ok("fw", [("state", "installed")]))
        default: connection.send(ControlLine.ok("fw", [("state", "writing"), ("next", "0")]))
        }
      default: connection.send(ControlLine.ok(request.verb))
      }
    }
    try server.start()
    defer { server.stop() }

    let model = DaemonModel(path: server.path, bundledFirmware: image)
    try await waitUntil { model.firmware == "0.2.1" }
    #expect(model.firmwareUpdateAvailable)
    model.updateFirmware()
    #expect(model.request?.kind == "firmware")
    try await waitUntil(seconds: 20) {
      if case .failed? = model.firmwareProgress { return true }
      return model.firmwareProgress == .done(version: "0.3.0")
    }
    #expect(model.firmwareProgress == .done(version: "0.3.0"))
    #expect(received.all.first == "begin" && received.all.last == "end")
    #expect(written == 400)
    #expect(model.request == nil)
    try await waitUntil { model.firmware == "0.3.0" }
    #expect(!model.firmwareUpdateAvailable)
  }
}
