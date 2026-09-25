import Foundation
import MacTouchKit

// mactouch piv pair|unpair: the Mac side of screen unlock, wrapping sc_auth.
// Everything else under `piv` goes to the device.

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
