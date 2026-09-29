import Foundation
import MacTouchKit
import Testing
@testable import MacTouchModel

/// Commands handed to the administrator prompt, safe to append from the
/// requests queue.
private final class Prompts: @unchecked Sendable {
  private let lock = NSLock()
  private var commands: [[String]] = []
  private var reasons: [String] = []
  func append(_ words: [String], _ prompt: String = "") { lock.lock(); commands.append(words); reasons.append(prompt); lock.unlock() }
  var all: [[String]] { lock.lock(); defer { lock.unlock() }; return commands }
  var prompts: [String] { lock.lock(); defer { lock.unlock() }; return reasons }
}

@MainActor
private func waitUntil(seconds: TimeInterval = 5, _ condition: @escaping () -> Bool) async throws {
  let deadline = Date().addingTimeInterval(seconds)
  while !condition() {
    try #require(Date() < deadline, "condition not met in time")
    try await Task.sleep(nanoseconds: 20_000_000)
  }
}

/// A connected sensor with two fingers and a card that has no keys yet.
private func fakeDaemon() throws -> ControlServer {
  let server = ControlServer(path: NSTemporaryDirectory() + "mactouch-setup-\(UUID().uuidString.prefix(8)).sock")
  server.handler = { request, connection in
    switch request.verb {
    case "events":
      connection.subscribed = true
      connection.send(ControlLine.evt("device", [("state", "connected")]))
    case "status":
      connection.send(ControlLine.ok("status", [
        ("device", "connected"), ("ring", "on:cyan"), ("layers", "idle"), ("monitors", "lock,mic,camera"),
        ("sensor", "ready"), ("prints", "2"), ("idle", "cyan"), ("fw", "0.2.2"),
      ]))
    case "piv":
      connection.send(ControlLine.ok("piv", [("enabled", "yes"), ("identity", "no"), ("pin", "default"), ("retries", "3"), ("flash", "encrypted")]))
    default:
      connection.send(ControlLine.ok(request.verb))
    }
  }
  try server.start()
  return server
}

private let installer = SudoInstaller(script: "/App/Resources/pam/pam-install.sh",
                                      module: "/App/Resources/pam/pam_mactouch.so",
                                      cli: "/App/Helpers/mactouch")

@Suite struct Setup {
  @Test @MainActor func turnsOnSudoThroughTheBundledScriptBehindOnePrompt() async throws {
    let server = try fakeDaemon()
    defer { server.stop() }
    let prompts = Prompts()
    let model = DaemonModel(path: server.path, sudoInstaller: installer) { words, prompt in
      prompts.append(words, prompt)
      return nil
    }
    try await waitUntil { model.daemonRunning }

    model.enableSudo()
    #expect(model.sudoSetup == .running)
    try await waitUntil { model.sudoSetup == nil }
    #expect(prompts.all == [["/usr/bin/env", "SUDO_USER=\(NSUserName())", installer.script,
                             "--module", installer.module, "--cli", installer.cli]])
    // The system prompt says what it is for, not "osascript wants to make changes".
    #expect(prompts.prompts == ["MacTouch wants to turn on sudo by fingerprint."])
    // The step reads its tick from the health report, so it is fresh afterwards.
    #expect(model.health != nil)
  }

  @Test @MainActor func saysWhySudoDidNotTurnOn() async throws {
    let server = try fakeDaemon()
    defer { server.stop() }
    let model = DaemonModel(path: server.path, sudoInstaller: installer) { _, _ in
      "Pairing failed. The device releases its key once per boot; replug it and run again."
    }
    try await waitUntil { model.daemonRunning }
    model.enableSudo()
    try await waitUntil { model.sudoSetup != .running }
    #expect(model.sudoSetup == .failed("Pairing failed. The device releases its key once per boot; replug it and run again."))
  }

  @Test @MainActor func withoutTheBundledPiecesSudoCannotBeTurnedOnHere() async throws {
    let server = try fakeDaemon()
    defer { server.stop() }
    let prompts = Prompts()
    let model = DaemonModel(path: server.path) { words, _ in prompts.append(words); return nil }
    try await waitUntil { model.daemonRunning }
    #expect(!model.canEnableSudo)
    model.enableSudo()
    #expect(model.sudoSetup == nil)
    #expect(prompts.all.isEmpty)
  }

  @Test @MainActor func stepsTickOffFromTheSensorsOwnState() async throws {
    let server = try fakeDaemon()
    defer { server.stop() }
    let model = DaemonModel(path: server.path)
    #expect(!model.isDone(.connect))
    try await waitUntil { model.deviceConnected && model.prints == 2 }
    model.refreshSmartCard()
    try await waitUntil { model.smartCard != nil }
    #expect(model.isDone(.connect))
    #expect(model.isDone(.firmware))
    #expect(model.isDone(.finger))
    #expect(!model.isDone(.smartCard))
    #expect(SetupStep.smartCard.isOptional)
    #expect(!SetupStep.finger.isOptional)
    // Until the health report arrives, whether sudo needs setting up is unknown.
    #expect(model.needsSetup == nil)
    model.refreshHealth()
    try await waitUntil { model.health != nil }
    #expect(model.needsSetup == !model.isDone(.sudo))
  }

  @Test func administratorErrorsReadAsSentences() {
    #expect(DaemonModel.administratorFailure(from: "0:130: execution error: Pairing failed. Replug it. (1)\n") == "Pairing failed. Replug it.")
    #expect(DaemonModel.administratorFailure(from: "0:52: execution error: User canceled. (-128)") == "cancelled")
    #expect(DaemonModel.administratorFailure(from: "something odd") == "something odd")
  }
}
