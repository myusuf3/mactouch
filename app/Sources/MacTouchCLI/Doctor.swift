import Foundation
import MacTouchKit

// mactouch doctor: turns the facts in `status` into verdicts, each with the
// fix. Works with or without the daemon; without it the device is asked
// directly.

struct Check {
  enum Verdict: String { case ok, warn, bad, off }
  let verdict: Verdict
  let name: String
  let detail: String
  init(_ verdict: Verdict, _ name: String, _ detail: String) {
    self.verdict = verdict; self.name = name; self.detail = detail
  }
}

func runDoctor(direct: Bool, port: String?) -> Int32 {
  var checks: [Check] = []
  var status: Fields?
  var selftest: (() throws -> Void)?

  let plist = NSHomeDirectory() + "/Library/LaunchAgents/dev.mactouch.daemon.plist"
  checks.append(FileManager.default.fileExists(atPath: plist)
    ? Check(.ok, "autostart", "launch agent installed, mactouchd starts at login")
    : Check(.off, "autostart", "no launch agent; scripts/install.sh installs one"))

  if !direct && ControlClient.isAvailable() {
    do {
      let client = try ControlClient()
      status = try client.request(ControlRequest(verb: "status"))
      checks.append(Check(.ok, "daemon", "running"))
      if status?["device"] == "connected" {
        selftest = { _ = try client.request(ControlRequest(verb: "selftest")) }
      }
    } catch {
      checks.append(Check(.bad, "daemon", "socket present but not answering (\(error)); scripts/daemon.sh restart"))
    }
    checks.append(deviceCheck(connected: status?["device"] == "connected", firmware: status?["fw"]))
  } else {
    checks.append(Check(direct ? .off : .warn, "daemon",
                        direct ? "skipped, --direct" : "not running; monitors, notify and hooks need it. scripts/daemon.sh start"))
    do {
      let device = try openDevice(port)
      status = try device.request(.status)
      checks.append(deviceCheck(connected: true, firmware: status?["fw"]))
      selftest = { try device.request(.selftest) }
    } catch let exit as Exit {
      checks.append(Check(.bad, "device", exit.message ?? "cannot open"))
    } catch DeviceError.notFound {
      checks.append(deviceCheck(connected: false, firmware: nil))
    } catch {
      checks.append(Check(.bad, "device", "\(error); replug the board"))
    }
  }

  switch status?["sensor"] {
  case "ready": checks.append(Check(.ok, "sensor", "ready"))
  case "offline": checks.append(Check(.bad, "sensor", "not answering; replug the device, and check the module wiring if it recurs"))
  default: checks.append(Check(.off, "sensor", "cannot check until the device is connected"))
  }

  if let selftest {
    do {
      try selftest()
      checks.append(Check(.ok, "signature", "firmware signs the shared protocol vector correctly"))
    } catch {
      checks.append("\(error)".contains("unknown")
        ? Check(.off, "signature", "cannot check; the firmware or mactouchd predates SELFTEST. Reflash, or scripts/daemon.sh restart")
        : Check(.bad, "signature", "firmware HMAC disagrees with docs/protocol-vectors.json (\(error)); reflash"))
    }
  }

  checks.append(pamCheck())

  if let prints = status?.int("prints") {
    checks.append(prints > 0
      ? Check(.ok, "fingers", "\(prints) enrolled")
      : Check(.warn, "fingers", "none enrolled; mactouch enroll 1"))
  }

  if let monitors = status?["monitors"] {
    if !monitors.split(separator: ",").contains("focus") {
      checks.append(Check(.off, "focus", "monitor off"))
    } else if status?["focus"] == "assertions" {
      checks.append(Check(.ok, "focus", "reads the Do Not Disturb store"))
    } else if status?["focus"] == nil {
      checks.append(Check(.off, "focus", "source unknown; the running mactouchd predates this check, scripts/daemon.sh restart"))
    } else {
      checks.append(Check(.warn, "focus", "menu bar fallback, cannot name the mode; grant mactouchd Full Disk Access in System Settings"))
    }
  }

  print("mactouch check-up")
  for check in checks {
    print("  \(check.verdict.rawValue.padding(toLength: 5, withPad: " ", startingAt: 0))" +
          "\(check.name.padding(toLength: 11, withPad: " ", startingAt: 0))\(check.detail)")
  }
  return checks.contains { $0.verdict == .bad } ? 1 : 0
}

/// Which PAM services name the module. The key itself is root-only, so this
/// reports installation, not pairing state.
private func pamCheck() -> Check {
  let module = "/usr/local/lib/pam/pam_mactouch.so"
  guard FileManager.default.fileExists(atPath: module) else {
    return Check(.off, "sudo", "pam_mactouch not installed; sudo scripts/pam-install.sh")
  }
  let files = (try? FileManager.default.contentsOfDirectory(atPath: "/etc/pam.d")) ?? []
  let services = files.sorted().filter { name in
    (try? String(contentsOfFile: "/etc/pam.d/" + name, encoding: .utf8))?.contains(module) ?? false
  }
  return services.isEmpty
    ? Check(.warn, "sudo", "module installed but no PAM service uses it; sudo scripts/pam-install.sh")
    : Check(.ok, "sudo", "fingerprint enabled for \(services.joined(separator: ", "))")
}

private func deviceCheck(connected: Bool, firmware: String?) -> Check {
  guard connected else {
    return Check(.bad, "device", "not found; use a data cable, and replug if the yellow heartbeat LED is blinking but the link is dead")
  }
  return Check(.ok, "device", firmware.map { "connected, firmware \($0)" } ?? "connected")
}
