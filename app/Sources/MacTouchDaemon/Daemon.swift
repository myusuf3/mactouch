import Foundation
import MacTouchKit

let protocolVersion = 1

/// The brain: owns the device, resolves the ring policy, serves the socket.
/// All state changes happen on `queue`; long device commands run off it so a
/// 60-second identify never blocks status or the ring.
final class Daemon {
  let queue = DispatchQueue(label: "mactouch.daemon")
  let manager = DeviceManager()
  let server: ControlServer
  let defaults = UserDefaults(suiteName: "dev.mactouch.daemon")!
  var policy = LEDPolicy(idle: .blue)
  var applied: RingState?
  var busy: String?
  var busyConnection: ControlConnection?
  var expiryTimer: DispatchSourceTimer?
  var monitors: Monitors!

  init(socketPath: String) {
    server = ControlServer(path: socketPath)
  }

  func start() throws {
    server.handler = { [weak self] request, connection in
      self?.queue.async { self?.handle(request, connection) }
    }
    server.onDisconnect = { [weak self] connection in
      self?.queue.async { if self?.busyConnection === connection { self?.busyConnection = nil } }
    }
    try server.start()
    log("listening on \(server.path)")

    monitors = Monitors(defaults: defaults) { [weak self] layer, state in
      self?.queue.async { self?.setLayer(layer, state) }
    }
    monitors.start()

    manager.onLog = { line in log(line) }
    manager.onConnect = { [weak self] device in self?.queue.async { self?.deviceConnected(device) } }
    manager.onDisconnect = { [weak self] in
      self?.queue.async {
        self?.applied = nil
        self?.server.broadcast(ControlLine.evt("device", [("state", "absent")]))
      }
    }
    manager.onEvent = { [weak self] name, fields in
      let line = ControlLine.evt(name.lowercased(), fields)
      self?.server.broadcast(line)
      self?.queue.async {
        if let connection = self?.busyConnection, !connection.subscribed { connection.send(line) }
      }
    }
    manager.start()
  }

  // MARK: ring

  private func deviceConnected(_ device: Device) {
    if ProcessInfo.processInfo.environment["MACTOUCH_DEBUG"] != nil {
      device.onRawLine = { log("< \($0)") }
      device.onRawWrite = { log("> \($0)") }
    }
    if let status = try? device.request(.status), let idle = status["idle"].flatMap(LEDColour.init) {
      policy.idle = idle
    }
    applied = nil
    applyRing()
    server.broadcast(ControlLine.evt("device", [("state", "connected")]))
  }

  private func setLayer(_ layer: RingLayer, _ state: RingState?) {
    if let state { policy.set(layer, state) } else { policy.clear(layer) }
    applyRing()
  }

  /// Sends the resolved state to the device when it differs from what the
  /// ring shows. Skipped while a long command owns the ring; re-run when it
  /// ends, because the device returns to its own idle colour then.
  private func applyRing() {
    policy.dropExpired()
    scheduleExpiry()
    guard busy == nil, let device = manager.device else { return }
    let state = policy.resolve()
    guard state != applied else { return }
    do {
      try device.request(state.command)
      applied = state
      log("ring \(state) layers=\(policy.active().map(\.name).joined(separator: ","))")
      server.broadcast(ControlLine.evt("ring", [("state", state.description)]))
    } catch {
      log("ring update failed: \(error)")
    }
  }

  private func scheduleExpiry() {
    expiryTimer?.cancel()
    expiryTimer = nil
    guard let next = policy.nextExpiry() else { return }
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + max(0.05, next.timeIntervalSinceNow))
    timer.setEventHandler { [weak self] in self?.applyRing() }
    expiryTimer = timer
    timer.resume()
  }

  // MARK: commands

  private func handle(_ request: ControlRequest, _ connection: ControlConnection) {
    let verb = request.verb
    func reply(_ fields: [(String, String)] = []) { connection.send(ControlLine.ok(verb, fields)) }
    func fail(_ reason: String) { connection.send(ControlLine.err(verb, reason)) }

    switch verb {
    case "ping":
      reply([("proto", "\(protocolVersion)"), ("device", manager.isConnected ? "connected" : "absent")])

    case "status":
      var fields: [(String, String)] = [
        ("proto", "\(protocolVersion)"),
        ("device", manager.isConnected ? "connected" : "absent"),
        ("ring", (applied ?? policy.resolve()).description),
        ("layers", policy.active().map(\.name).joined(separator: ",")),
        ("monitors", monitors.enabledNames.joined(separator: ",")),
        ("busy", busy ?? "none"),
      ]
      if busy == nil, let device = manager.device, let status = try? device.request(.status) {
        for key in ["fw", "sensor", "prints", "touch", "watch", "idle"] {
          if let value = status[key] { fields.append((key, value)) }
        }
      }
      reply(fields)

    case "led":
      guard let modeName = request.positional.first, let mode = LEDMode(rawValue: modeName) else { return fail("mode") }
      var colour = LEDColour.off, colour2: LEDColour? = nil
      if mode != .off {
        guard request.positional.count >= 2, let c = LEDColour(rawValue: request.positional[1]) else { return fail("colour") }
        colour = c
        if request.positional.count >= 3 {
          guard let c2 = LEDColour(rawValue: request.positional[2]) else { return fail("colour") }
          colour2 = c2
        }
      }
      policy.set(.notify, RingState(mode, colour, colour2), for: request.double("for"))
      applyRing()
      reply()

    case "notify":
      guard let name = request.positional.first, let colour = LEDColour(rawValue: name) else { return fail("colour") }
      let mode = request["mode"].flatMap(LEDMode.init) ?? .on
      guard let seconds = request.double("for"), seconds > 0 else { return fail("for") }
      policy.set(.notify, RingState(mode, colour), for: seconds)
      applyRing()
      reply()

    case "clear":
      policy.clear(.notify)
      applyRing()
      reply()

    case "idle":
      guard let name = request.positional.first, let colour = LEDColour(rawValue: name) else { return fail("colour") }
      guard let device = manager.device else { return fail("device") }
      do {
        try device.request(.idle(colour))
        policy.idle = colour
        applied = .steady(colour)
        applyRing()
        reply()
      } catch { fail(describe(error)) }

    case "identify":
      let seconds = request.double("timeout") ?? 15
      guard seconds >= 1, seconds <= 120 else { return fail("timeout") }
      let nonce = request["nonce"]
      let prompt = request["prompt"].flatMap(LEDColour.init) ?? (nonce == nil ? .blue : .white)
      let reason = request["reason"] ?? (nonce == nil ? "A program asked for your fingerprint" : "sudo asked for your fingerprint")
      runLong(verb, connection, timeout: seconds + 3) { device in
        postNotification(title: "mactouch", body: reason)
        return try device.request(.identify(timeoutMs: Int(seconds * 1000), prompt: prompt, nonce: nonce), timeout: seconds + 3)
      }

    case "enroll":
      guard let slot = request.int("slot"), (1...20).contains(slot) else { return fail("slot") }
      runLong(verb, connection, timeout: 50) { device in
        try device.request(.enroll(slot: slot), timeout: 50)
      }

    case "pair":
      let seconds = request.double("timeout") ?? 30
      runLong(verb, connection, timeout: seconds + 3) { device in
        postNotification(title: "mactouch", body: "Touch to release the device key")
        return try device.request(.pair(timeoutMs: Int(seconds * 1000)), timeout: seconds + 3)
      }

    case "delete":
      if request.positional.first == "all" {
        passthrough(.deleteAll, verb, connection)
      } else if let slot = request.int("slot") {
        passthrough(.delete(slot: slot), verb, connection)
      } else { fail("slot") }

    case "slots": passthrough(.slots, verb, connection)
    case "gpio": passthrough(.gpio, verb, connection)
    case "watch":
      guard let value = request.positional.first, value == "on" || value == "off" else { return fail("value") }
      passthrough(.watch(value == "on"), verb, connection)
    case "touch":
      guard let source = request.positional.first.flatMap(TouchSource.init) else { return fail("value") }
      passthrough(.touch(source), verb, connection)
    case "cancel": passthrough(.cancel, verb, connection)
    case "reboot": passthrough(.reboot, verb, connection)

    case "monitor":
      guard request.positional.count == 2, let name = MonitorName(rawValue: request.positional[0]),
            request.positional[1] == "on" || request.positional[1] == "off" else { return fail("value") }
      monitors.set(name, enabled: request.positional[1] == "on")
      reply()

    case "events":
      connection.subscribed = true
      connection.send(ControlLine.evt("device", [("state", manager.isConnected ? "connected" : "absent")]))

    default:
      fail("unknown")
    }
  }

  /// A short device command answered inline.
  private func passthrough(_ command: Command, _ verb: String, _ connection: ControlConnection) {
    guard busy == nil else { return connection.send(ControlLine.err(verb, "busy")) }
    guard let device = manager.device else { return connection.send(ControlLine.err(verb, "device")) }
    do {
      let fields = try device.request(command)
      connection.send(ControlLine.ok(verb, fields.values.keys.sorted().map { ($0, fields.values[$0]!) }))
    } catch {
      connection.send(ControlLine.err(verb, describe(error)))
    }
  }

  /// A command that waits on the user. Runs off the daemon queue; only one at
  /// a time. The ring belongs to the device until it finishes.
  private func runLong(_ verb: String, _ connection: ControlConnection, timeout: TimeInterval,
                       _ body: @escaping (Device) throws -> Fields) {
    guard busy == nil else { return connection.send(ControlLine.err(verb, "busy")) }
    guard let device = manager.device else { return connection.send(ControlLine.err(verb, "device")) }
    busy = verb
    busyConnection = connection
    DispatchQueue.global().async { [weak self] in
      let outcome: Result<Fields, Error> = Result { try body(device) }
      self?.queue.async {
        guard let self else { return }
        self.busy = nil
        self.busyConnection = nil
        switch outcome {
        case .success(let fields):
          connection.send(ControlLine.ok(verb, fields.values.keys.sorted().map { ($0, fields.values[$0]!) }))
        case .failure(let error):
          connection.send(ControlLine.err(verb, describe(error)))
        }
        // The device returns to its own idle colour after a long command.
        self.applied = nil
        self.applyRing()
      }
    }
  }
}

private func describe(_ error: Error) -> String {
  if case DeviceError.rejected(_, let reason) = error { return reason }
  if case DeviceError.timeout = error { return "device_timeout" }
  if case DeviceError.disconnected = error { return "device" }
  return "\(error)"
}

func postNotification(title: String, body: String) {
  let escape = { (s: String) in s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
  let script = "display notification \"\(escape(body))\" with title \"\(escape(title))\""
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
  process.arguments = ["-e", script]
  process.standardOutput = FileHandle.nullDevice
  process.standardError = FileHandle.nullDevice
  try? process.run()
}

func log(_ message: String) {
  let stamp = ISO8601DateFormatter().string(from: Date())
  FileHandle.standardError.write(Data("\(stamp) \(message)\n".utf8))
}
