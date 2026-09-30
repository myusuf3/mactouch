import Foundation
import MacTouchKit
import Testing
@testable import MacTouchModel

/// Commands handed to the administrator prompt and what the prompt said,
/// safe to append from the requests queue.
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

/// A scratch stand-in for /etc/pam.d and /usr/local/bin, gone afterwards.
private struct Scratch {
  let root = NSTemporaryDirectory() + "mactouch-scratch-\(UUID().uuidString.prefix(8))"
  var pam: String { root + "/pam.d" }
  var link: String { root + "/bin/mactouch" }

  init() throws {
    try FileManager.default.createDirectory(atPath: pam, withIntermediateDirectories: true)
  }

  /// What pam-install.sh leaves behind for sudo.
  func turnOnSudo() {
    try? "auth       sufficient     \(PAMConfig.module)\n".write(toFile: pam + "/sudo_local", atomically: true, encoding: .utf8)
  }

  func turnOffSudo() {
    try? "# sudo_local\n".write(toFile: pam + "/sudo_local", atomically: true, encoding: .utf8)
  }

  func remove() { try? FileManager.default.removeItem(atPath: root) }
}

private let tools = BundledTools(pamInstall: "/App/Resources/pam/pam-install.sh",
                                 pamUninstall: "/App/Resources/pam/pam-uninstall.sh",
                                 pamModule: "/App/Resources/pam/pam_mactouch.so",
                                 cli: "/App/MacTouch.app/Contents/Helpers/mactouch")

@Suite struct Setup {
  @Test @MainActor func turnsOnSudoThroughTheBundledScriptBehindOnePrompt() async throws {
    let server = try fakeDaemon()
    defer { server.stop() }
    let scratch = try Scratch()
    defer { scratch.remove() }
    let prompts = Prompts()
    let model = DaemonModel(path: server.path, tools: tools, pamDirectory: scratch.pam, commandLineLink: scratch.link) { words, prompt in
      prompts.append(words, prompt)
      scratch.turnOnSudo()
      return nil
    }
    try await waitUntil { model.daemonRunning }
    model.refreshHealth()
    try await waitUntil { model.pamServices != nil }
    #expect(!model.isDone(.sudo))

    model.enableSudo()
    #expect(model.sudoTask == .running)
    try await waitUntil { model.sudoTask == nil && model.isDone(.sudo) }
    #expect(prompts.all == [["/usr/bin/env", "SUDO_USER=\(NSUserName())", tools.pamInstall,
                             "--module", tools.pamModule, "--cli", tools.cli]])
    // The system prompt says what it is for, not "osascript wants to make changes".
    #expect(prompts.prompts == ["MacTouch wants to turn on sudo by fingerprint."])
  }

  @Test @MainActor func turnsOffSudoWithTheBundledUninstallScript() async throws {
    let server = try fakeDaemon()
    defer { server.stop() }
    let scratch = try Scratch()
    defer { scratch.remove() }
    scratch.turnOnSudo()
    let prompts = Prompts()
    let model = DaemonModel(path: server.path, tools: tools, pamDirectory: scratch.pam, commandLineLink: scratch.link) { words, prompt in
      prompts.append(words, prompt)
      scratch.turnOffSudo()
      return nil
    }
    model.refreshHealth()
    try await waitUntil { model.isDone(.sudo) }

    model.disableSudo()
    try await waitUntil { model.sudoTask == nil && !model.isDone(.sudo) }
    #expect(prompts.all == [[tools.pamUninstall]])
    #expect(prompts.prompts == ["MacTouch wants to turn off sudo by fingerprint."])
  }

  @Test @MainActor func sudoMeansTheSudoServiceNotAnyService() async throws {
    let server = try fakeDaemon()
    defer { server.stop() }
    let scratch = try Scratch()
    defer { scratch.remove() }
    // su still uses the module after sudo has been turned off.
    try "auth       sufficient     \(PAMConfig.module)\n".write(toFile: scratch.pam + "/su", atomically: true, encoding: .utf8)
    let model = DaemonModel(path: server.path, pamDirectory: scratch.pam, commandLineLink: scratch.link)
    model.refreshHealth()
    try await waitUntil { model.pamServices == ["su"] }
    #expect(!model.isDone(.sudo))
    #expect(model.needsSetup == true)
  }

  @Test @MainActor func saysWhySudoDidNotTurnOn() async throws {
    let server = try fakeDaemon()
    defer { server.stop() }
    let scratch = try Scratch()
    defer { scratch.remove() }
    let model = DaemonModel(path: server.path, tools: tools, pamDirectory: scratch.pam, commandLineLink: scratch.link) { _, _ in
      "Pairing failed. The device releases its key once per boot; replug it and run again."
    }
    try await waitUntil { model.daemonRunning }
    model.enableSudo()
    try await waitUntil { model.sudoTask != .running }
    #expect(model.sudoTask == .failed("Pairing failed. The device releases its key once per boot; replug it and run again."))
  }

  @Test @MainActor func withoutTheBundledToolsNothingIsOffered() async throws {
    let server = try fakeDaemon()
    defer { server.stop() }
    let scratch = try Scratch()
    defer { scratch.remove() }
    let prompts = Prompts()
    let model = DaemonModel(path: server.path, pamDirectory: scratch.pam, commandLineLink: scratch.link) { words, _ in prompts.append(words); return nil }
    try await waitUntil { model.daemonRunning }
    #expect(!model.canChangeSudo)
    model.enableSudo()
    model.disableSudo()
    model.installCommandLineTool()
    #expect(model.sudoTask == nil)
    #expect(model.commandLineTask == nil)
    #expect(prompts.all.isEmpty)
    model.refreshHealth()
    try await waitUntil { model.pamServices != nil }
    #expect(model.commandLineTool == nil)
  }

  @Test @MainActor func stepsTickOffFromTheSensorsOwnState() async throws {
    let server = try fakeDaemon()
    defer { server.stop() }
    let scratch = try Scratch()
    defer { scratch.remove() }
    let model = DaemonModel(path: server.path, pamDirectory: scratch.pam, commandLineLink: scratch.link)
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
    // Until the Mac's PAM files have been read, whether sudo needs setting up is unknown.
    #expect(model.needsSetup == nil)
    scratch.turnOnSudo()
    model.refreshHealth()
    try await waitUntil { model.pamServices != nil }
    #expect(model.needsSetup == false)
  }

  @Test func administratorErrorsReadAsSentences() {
    #expect(DaemonModel.administratorFailure(from: "0:130: execution error: Pairing failed. Replug it. (1)\n") == "Pairing failed. Replug it.")
    #expect(DaemonModel.administratorFailure(from: "0:52: execution error: User canceled. (-128)") == "cancelled")
    #expect(DaemonModel.administratorFailure(from: "something odd") == "something odd")
  }
}

@Suite struct CommandLineLinks {
  private let cli = "/Applications/MacTouch.app/Contents/Helpers/mactouch"

  private func scratchLink(pointingAt target: String?) throws -> (link: String, root: String) {
    let root = NSTemporaryDirectory() + "mactouch-link-\(UUID().uuidString.prefix(8))"
    try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    let link = root + "/mactouch"
    if let target { try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target) }
    return (link, root)
  }

  @Test func readsWhatIsAtThePath() throws {
    let absent = try scratchLink(pointingAt: nil)
    #expect(CommandLineTool.status(at: absent.link, for: cli) == .absent)
    let ours = try scratchLink(pointingAt: cli)
    #expect(CommandLineTool.status(at: ours.link, for: cli) == .installed)
    let old = try scratchLink(pointingAt: "/Users/someone/Applications/MacTouch.app/Contents/Helpers/mactouch")
    #expect(CommandLineTool.status(at: old.link, for: cli) == .stale)
    let foreign = try scratchLink(pointingAt: "/opt/homebrew/bin/mactouch")
    #expect(CommandLineTool.status(at: foreign.link, for: cli) == .occupied)
    let file = try scratchLink(pointingAt: nil)
    try "#!/bin/sh\n".write(toFile: file.link, atomically: true, encoding: .utf8)
    #expect(CommandLineTool.status(at: file.link, for: cli) == .occupied)
    for scratch in [absent, ours, old, foreign, file] { try? FileManager.default.removeItem(atPath: scratch.root) }
  }

  @Test @MainActor func installsAndRemovesTheLinkBehindThePrompt() async throws {
    let server = try fakeDaemon()
    defer { server.stop() }
    let scratch = try Scratch()
    defer { scratch.remove() }
    let prompts = Prompts()
    let model = DaemonModel(path: server.path, tools: tools, pamDirectory: scratch.pam, commandLineLink: scratch.link) { words, prompt in
      prompts.append(words, prompt)
      // Run what root would run, here as this user in the scratch folder.
      let process = Process()
      process.executableURL = URL(fileURLWithPath: words[0])
      process.arguments = Array(words.dropFirst())
      try? process.run()
      process.waitUntilExit()
      return process.terminationStatus == 0 ? nil : "failed"
    }
    model.refreshHealth()
    try await waitUntil { model.commandLineTool == .absent }

    model.installCommandLineTool()
    try await waitUntil { model.commandLineTool == .installed && model.commandLineTask == nil }
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: scratch.link) == tools.cli)
    #expect(prompts.prompts.last == "MacTouch wants to put the mactouch command in /usr/local/bin.")

    model.removeCommandLineTool()
    try await waitUntil { model.commandLineTool == .absent && model.commandLineTask == nil }
    #expect(prompts.all.last == ["/bin/rm", "-f", scratch.link])
  }

  @Test @MainActor func leavesSomethingElsesCommandAlone() async throws {
    let server = try fakeDaemon()
    defer { server.stop() }
    let scratch = try Scratch()
    defer { scratch.remove() }
    try FileManager.default.createDirectory(atPath: scratch.root + "/bin", withIntermediateDirectories: true)
    try "#!/bin/sh\n".write(toFile: scratch.link, atomically: true, encoding: .utf8)
    let prompts = Prompts()
    let model = DaemonModel(path: server.path, tools: tools, pamDirectory: scratch.pam, commandLineLink: scratch.link) { words, _ in
      prompts.append(words)
      return nil
    }
    model.refreshHealth()
    try await waitUntil { model.commandLineTool == .occupied }
    model.installCommandLineTool()
    model.removeCommandLineTool()
    #expect(prompts.all.isEmpty)
    #expect(model.commandLineTask == nil)
  }
}
