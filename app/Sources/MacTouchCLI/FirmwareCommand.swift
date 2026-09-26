import Foundation
import MacTouchKit

// mactouch firmware version|update [image]: the board's firmware over the
// link, ADR-0018. Without an image, the one MacTouch.app carries.

/// The image inside the app bundle this CLI came from, when it came from one.
func bundledFirmware() -> URL? {
  // argv[0] is just "mactouch" when it came from PATH; the executable URL is
  // the real file, and resolving it follows ~/.local/bin into the bundle.
  guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return nil }
  let resources = executable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")
  let url = resources.appendingPathComponent("firmware/mactouch.bin")
  return FileManager.default.fileExists(atPath: url.path) ? url : nil
}

func runFirmware(_ args: [String], direct: Bool, port: String?) throws -> Int32 {
  guard let sub = args.first, ["version", "update"].contains(sub) else { throw fail("firmware version|update [image]") }
  guard let url = args.count > 1 ? URL(fileURLWithPath: args[1]) : bundledFirmware() else {
    throw fail("no firmware image given and none bundled with MacTouch.app")
  }
  let image = try FirmwareImage(contentsOf: url)
  guard image.isMactouch else { throw FirmwareError.notMactouch }

  let viaDaemon = !direct && ControlClient.isAvailable()
  let device = viaDaemon ? nil : try openDevice(port)
  let client = viaDaemon ? try ControlClient() : nil
  let status = try client?.request(ControlRequest(verb: "status")) ?? device!.request(.status)
  let running = status["fw"] ?? "unknown"
  print("board \(running) in \(status["slot"] ?? "?"), image \(image.version ?? "unknown")")
  if sub == "version" { return 0 }

  let updater = FirmwareUpdater(image: image) { step, timeout in
    if let client { return try client.request(.firmware(step), timeout: timeout) }
    return try device!.request(.fw(step), timeout: timeout)
  }
  var lastPercent = -1
  try updater.run { step in
    switch step {
    case .waitingForTouch: print("touch the sensor to allow the update")
    case .writing(let done, let total):
      let percent = done * 100 / total
      if percent / 10 != lastPercent / 10 { print("  \(percent)%"); lastPercent = percent }
    case .installing: print("checking and installing; the board restarts")
    }
  }
  client?.close()
  device?.close()
  print("waiting for the board to restart")
  let outcome = FirmwareUpdater.awaitOutcome(for: image, status: { boardStatus(direct: !viaDaemon, port: port) },
                                             onProbation: { print("running \(image.version ?? "it") on probation; waiting for it to confirm itself") })
  switch outcome {
  case .confirmed(let version, let slot):
    print("running \(version) from \(slot), confirmed")
    return 0
  case .rolledBack(let version):
    throw fail("the board is back on \(version ?? "unknown"): the new image failed and it rolled back")
  case .notBack:
    throw fail("the board did not come back; if it stays away, scripts/flash.sh recovers it")
  case .stillOnProbation:
    throw fail("the new image is still on probation after 90 seconds; check mactouch status")
  }
}

/// The board's status once, or nil while it is away. Right after a
/// reconnect the daemon knows the board is there before it has asked it
/// anything, so a status without a version is treated as no answer.
private func boardStatus(direct: Bool, port: String?) -> Fields? {
  if direct {
    guard let device = try? openDevice(port) else { return nil }
    defer { device.close() }
    return try? device.request(.status)
  }
  guard let client = try? ControlClient() else { return nil }
  defer { client.close() }
  guard let status = try? client.request(ControlRequest(verb: "status")), status["device"] == "connected" else { return nil }
  return status
}
