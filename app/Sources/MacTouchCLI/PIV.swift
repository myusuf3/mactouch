import Foundation
import MacTouchKit

// mactouch piv pair|unpair: the Mac side of screen unlock, wrapping sc_auth.
// Everything else under `piv` goes to the device.

let pivUsage = "piv status|on|off|genkey|reset|mode pin|password|pair|unpair"

/// `piv mode <pin|password>`.
func unlockMode(_ args: [String]) throws -> UnlockMode {
  guard args.count == 2, let mode = UnlockMode(rawValue: args[1]) else { throw fail("piv mode pin|password") }
  return mode
}

/// From the terminal with echo off, so it never shows or reaches history.
func readPassword(_ prompt: String = "Your Mac password: ") throws -> String {
  var buffer = [CChar](repeating: 0, count: 256)
  defer { _ = buffer.withUnsafeMutableBytes { memset_s($0.baseAddress, $0.count, 0, $0.count) } }
  guard let read = readpassphrase(prompt, &buffer, buffer.count, 0) else {
    throw fail("cannot read a password here; run it in a terminal")
  }
  return String(cString: read)
}

func runPIVPair() throws -> Int32 {
  let card = try cardStatus()
  guard card["pin"] != "default" else {
    throw fail("the card's PIN is still the default 123456; change it first with sc_auth changepin (6 to 8 digits)")
  }
  guard let identities = SmartCardIdentities.current() else { throw fail("cannot run sc_auth") }
  if let paired = identities.paired.first {
    print("already paired: \(paired.hash)")
    return 0
  }
  guard let identity = identities.unpaired.first else {
    throw fail("macOS lists no mactouch identity. Is the card on (mactouch piv on) with an identity (mactouch piv genkey)?")
  }
  print("""
  This pairs the card with your account, so the lock screen and login window
  accept its PIN followed by a touch. Before you continue:
    - keep your password; pairing adds a way in and removes none
    - do not turn on smart card enforcement, in System Settings or a profile
    - keep a second admin account on this Mac
  Identity: \(identity.hash)
  Type pair to continue:
  """, terminator: " ")
  guard readLine()?.trimmingCharacters(in: .whitespaces) == "pair" else { throw Exit(code: 2, message: "not paired") }
  return scAuth(["pair", "-u", NSUserName(), "-h", identity.hash])
}

func runPIVUnpair() throws -> Int32 {
  guard let identities = SmartCardIdentities.current() else { throw fail("cannot run sc_auth") }
  guard !identities.paired.isEmpty else {
    print("nothing paired for this device")
    return 0
  }
  for identity in identities.paired {
    let code = scAuth(["unpair", "-u", NSUserName(), "-h", identity.hash])
    if code != 0 { return code }
  }
  return 0
}

/// The device's own view of the card, through the daemon when it runs.
private func cardStatus() throws -> Fields {
  if ControlClient.isAvailable() {
    let client = try ControlClient()
    defer { client.close() }
    return try client.request(ControlRequest(verb: "piv", positional: ["status"]))
  }
  let device = try openDevice(nil)
  defer { device.close() }
  return try device.request(.piv("STATUS"))
}

/// Pairing changes the user's keychain and needs an administrator, so it
/// runs under sudo, which asks the ring itself when pam_mactouch is on.
private func scAuth(_ arguments: [String]) -> Int32 {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
  process.arguments = ["/usr/sbin/sc_auth"] + arguments
  do { try process.run() } catch { return 1 }
  process.waitUntilExit()
  return process.terminationStatus
}

/// mactouch password list|add|remove: which apps and sites get which
/// password, ADR-0023. mactouchd keeps them, so it must be running.
func runPasswordTargets(_ args: [String]) throws -> Int32 {
  guard ControlClient.isAvailable() else { throw fail("password needs mactouchd running; it keeps the passwords in your keychain") }
  let client = try ControlClient()
  defer { client.close() }
  let usage = "password list | add app <bundle-id>|site <host> [--mac] | remove app <bundle-id>|site <host>"
  if args.first == "list" {
    let reply = try client.request(ControlRequest(verb: "targets"))
    let targets = try PasswordTarget.decode(reply["list"] ?? "")
    let terminals = Set(PasswordTargets.builtIn.values).subtracting(["the login window", "a system dialog"])
      .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    print("always your Mac password: the lock screen, system prompts, \(terminals.joined(separator: ", "))")
    for target in targets {
      print("\(target.kind.rawValue)\t\(target.id)\t\(target.uses == .mac ? "Mac password" : "own password")")
    }
    if reply["accessibility"] == "no", targets.contains(where: { $0.kind == .site }) {
      print("sites are not matched until mactouchd is allowed in System Settings, Privacy & Security, Accessibility")
    }
    return 0
  }
  guard args.count >= 3, let kind = PasswordTarget.Kind(rawValue: args[1]) else { throw fail(usage) }
  var values = ["kind": kind.rawValue, "id": args[2]]
  if args[0] == "add" {
    let mac = args.dropFirst(3).contains("--mac")
    values["uses"] = mac ? "mac" : "own"
    if !mac { values["hex"] = Data(try readPassword("Password for \(args[2]): ").utf8).map { String(format: "%02x", $0) }.joined() }
  }
  _ = try client.request(ControlRequest(verb: "target", positional: [args[0] == "add" ? "set" : "remove"], values: values))
  return 0
}
