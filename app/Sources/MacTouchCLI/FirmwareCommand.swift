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
    if let client {
      let words = step.split(separator: " ").map(String.init)
      var request = ControlRequest(verb: "fw", positional: [words[0].lowercased()])
      for word in words.dropFirst() {
        guard let eq = word.firstIndex(of: "=") else { continue }
        request.values[String(word[..<eq])] = String(word[word.index(after: eq)...])
      }
      return try client.request(request, timeout: timeout)
    }
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
  // A new image is on probation until it has run healthily for a while, and
  // a crash in that time rolls the board back. Only the end of probation
  // says the update took; seeing the new version once does not.
  let deadline = Date().addingTimeInterval(90)
  var seenNew = false
  while Date() < deadline {
    guard let back = waitForBoard(timeout: 40, direct: !viaDaemon, port: port) else {
      throw fail("the board did not come back within 40 seconds; if it stays away, scripts/flash.sh recovers it")
    }
    if back["fw"] != image.version {
      throw fail("the board is back on \(back["fw"] ?? "unknown") in \(back["slot"] ?? "?"): the new image failed and it rolled back")
    }
    if back["probation"] != "yes" {
      print("running \(back["fw"]!) from \(back["slot"] ?? "?"), confirmed")
      return 0
    }
    if !seenNew { print("running \(back["fw"]!) on probation; waiting for it to confirm itself"); seenNew = true }
    Thread.sleep(forTimeInterval: 2)
  }
  throw fail("the new image is still on probation after 90 seconds; check mactouch status")
}

/// Polls until the board answers status again after its restart.
private func waitForBoard(timeout: TimeInterval, direct: Bool, port: String?) -> Fields? {
  let deadline = Date().addingTimeInterval(timeout)
  Thread.sleep(forTimeInterval: 2)
  while Date() < deadline {
    if direct {
      if let device = try? openDevice(port) {
        defer { device.close() }
        if let status = try? device.request(.status), status["fw"] != nil { return status }
      }
    } else if let client = try? ControlClient() {
      defer { client.close() }
      // Right after a reconnect the daemon knows the board is there before
      // it has asked it anything; a status without a version is not an answer.
      if let status = try? client.request(ControlRequest(verb: "status")), status["device"] == "connected",
         status["fw"] != nil { return status }
    }
    Thread.sleep(forTimeInterval: 1)
  }
  return nil
}
