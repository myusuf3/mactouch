import Foundation

/// One verdict from the check-up, with the fix in `detail`.
public struct HealthCheck: Equatable, Sendable {
  public enum Verdict: String, Sendable { case ok, warn, bad, off }
  public let verdict: Verdict
  public let name: String
  public let detail: String
  public init(_ verdict: Verdict, _ name: String, _ detail: String) {
    self.verdict = verdict; self.name = name; self.detail = detail
  }
}

/// The facts in `status` turned into verdicts. `mactouch doctor` and the
/// app's Diagnostics pane render this one list.
public struct HealthReport: Sendable {
  public let checks: [HealthCheck]
  public var healthy: Bool { !checks.contains { $0.verdict == .bad } }

  /// Asks the running daemon.
  public static func viaDaemon(at path: String = ControlSocketPath.default) -> HealthReport {
    var checks = [autostartCheck()]
    var status: Fields?
    var selftest: Result<Void, Error>?
    do {
      let client = try ControlClient(path: path)
      defer { client.close() }
      status = try client.request(ControlRequest(verb: "status"))
      checks.append(HealthCheck(.ok, "daemon", "running"))
      if status?["device"] == "connected" {
        selftest = Result { _ = try client.request(ControlRequest(verb: "selftest")) }
      }
    } catch {
      checks.append(HealthCheck(.bad, "daemon", "socket present but not answering (\(error)); scripts/daemon.sh restart"))
    }
    checks.append(deviceCheck(connected: status?["device"] == "connected", firmware: status?["fw"]))
    return HealthReport(checks: checks + statusChecks(status, selftest: selftest))
  }

  /// Asks the device over its serial port. `daemonSkipped` says the caller
  /// bypassed a daemon on purpose rather than finding none.
  public static func viaDevice(port: String? = nil, daemonSkipped: Bool) -> HealthReport {
    var checks = [autostartCheck()]
    checks.append(daemonSkipped
      ? HealthCheck(.off, "daemon", "skipped, --direct")
      : HealthCheck(.warn, "daemon", "not running; monitors, notify and hooks need it. scripts/daemon.sh start"))
    var status: Fields?
    var selftest: Result<Void, Error>?
    do {
      let device = try port.map(Device.init(path:)) ?? Device()
      defer { device.close() }
      status = try device.request(.status)
      checks.append(deviceCheck(connected: true, firmware: status?["fw"]))
      selftest = Result { _ = try device.request(.selftest) }
    } catch DeviceError.notFound {
      checks.append(deviceCheck(connected: false, firmware: nil))
    } catch DeviceError.openFailed(let path, let code) where code == EBUSY {
      checks.append(HealthCheck(.bad, "device", "\(path) is held by another process, probably mactouchd; stop it or drop --direct"))
    } catch {
      checks.append(HealthCheck(.bad, "device", "\(error); replug the board"))
    }
    return HealthReport(checks: checks + statusChecks(status, selftest: selftest))
  }

  private static func statusChecks(_ status: Fields?, selftest: Result<Void, Error>?) -> [HealthCheck] {
    var checks: [HealthCheck] = []

    switch status?["sensor"] {
    case "ready": checks.append(HealthCheck(.ok, "sensor", "ready"))
    case "offline": checks.append(HealthCheck(.bad, "sensor", "not answering; replug the device, and check the module wiring if it recurs"))
    default: checks.append(HealthCheck(.off, "sensor", "cannot check until the device is connected"))
    }

    switch selftest {
    case .success:
      checks.append(HealthCheck(.ok, "signature", "firmware signs the shared protocol vector correctly"))
    case .failure(let error):
      checks.append("\(error)".contains("unknown")
        ? HealthCheck(.off, "signature", "cannot check; the firmware or mactouchd predates SELFTEST. Reflash, or scripts/daemon.sh restart")
        : HealthCheck(.bad, "signature", "firmware HMAC disagrees with docs/protocol-vectors.json (\(error)); reflash"))
    case nil: break
    }

    checks.append(pamCheck())

    if let prints = status?.int("prints") {
      checks.append(prints > 0
        ? HealthCheck(.ok, "fingers", "\(prints) enrolled")
        : HealthCheck(.warn, "fingers", "none enrolled; mactouch enroll 1"))
    }

    if let piv = status?["piv"] { checks.append(pivCheck(piv)) }

    if let monitors = status?["monitors"] {
      if !monitors.split(separator: ",").contains("focus") {
        checks.append(HealthCheck(.off, "focus", "monitor off"))
      } else if status?["focus"] == "assertions" {
        checks.append(HealthCheck(.ok, "focus", "reads the Do Not Disturb store"))
      } else if status?["focus"] == nil {
        checks.append(HealthCheck(.off, "focus", "source unknown; the running mactouchd predates this check, scripts/daemon.sh restart"))
      } else {
        checks.append(HealthCheck(.warn, "focus", "menu bar fallback, cannot name the mode; grant mactouchd Full Disk Access in System Settings"))
      }
    }
    return checks
  }

  /// Whether launchd has the daemon's agent, from the plist inside
  /// MacTouch.app that the app registers or the one install.sh writes.
  /// The smart card side, docs/PIV.md: off, on without an identity, ready
  /// but unpaired, or paired for login and unlock.
  private static func pivCheck(_ piv: String) -> HealthCheck {
    switch piv {
    case "off": return HealthCheck(.off, "unlock", "smart card off; mactouch piv on")
    case "none": return HealthCheck(.warn, "unlock", "smart card on but it has no identity; mactouch piv genkey")
    default: break
    }
    guard let identities = SmartCardIdentities.current() else {
      return HealthCheck(.off, "unlock", "identity ready; cannot ask sc_auth about pairing")
    }
    if !identities.paired.isEmpty { return HealthCheck(.ok, "unlock", "smart card paired; PIN then touch unlocks") }
    if !identities.unpaired.isEmpty { return HealthCheck(.warn, "unlock", "identity ready, not paired; mactouch piv pair") }
    return HealthCheck(.warn, "unlock", "identity ready but macOS does not list it; replug the device")
  }

  private static func autostartCheck() -> HealthCheck {
    let launchctl = Process()
    launchctl.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    launchctl.arguments = ["print", "gui/\(getuid())/dev.mactouch.daemon"]
    let output = Pipe()
    launchctl.standardOutput = output
    launchctl.standardError = FileHandle.nullDevice
    guard (try? launchctl.run()) != nil else {
      return HealthCheck(.off, "autostart", "cannot ask launchctl about the agent")
    }
    let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    launchctl.waitUntilExit()
    guard launchctl.terminationStatus == 0 else {
      return HealthCheck(.off, "autostart", "no launch agent; open MacTouch.app, or scripts/install.sh for a checkout")
    }
    let source = text.contains("com.apple.xpc.ServiceManagement") ? "MacTouch.app" : "scripts/install.sh"
    return HealthCheck(.ok, "autostart", "launch agent from \(source), mactouchd starts at login")
  }

  /// Which PAM services name the module. The key itself is root-only, so this
  /// reports installation, not pairing state.
  private static func pamCheck() -> HealthCheck {
    let module = "/usr/local/lib/pam/pam_mactouch.so"
    guard FileManager.default.fileExists(atPath: module) else {
      return HealthCheck(.off, "sudo", "pam_mactouch not installed; sudo scripts/pam-install.sh")
    }
    let files = (try? FileManager.default.contentsOfDirectory(atPath: "/etc/pam.d")) ?? []
    let services = files.sorted().filter { name in
      (try? String(contentsOfFile: "/etc/pam.d/" + name, encoding: .utf8))?.contains(module) ?? false
    }
    return services.isEmpty
      ? HealthCheck(.warn, "sudo", "module installed but no PAM service uses it; sudo scripts/pam-install.sh")
      : HealthCheck(.ok, "sudo", "fingerprint enabled for \(services.joined(separator: ", "))")
  }

  private static func deviceCheck(connected: Bool, firmware: String?) -> HealthCheck {
    guard connected else {
      return HealthCheck(.bad, "device", "not found; use a data cable, and replug if the yellow heartbeat LED is blinking but the link is dead")
    }
    return HealthCheck(.ok, "device", firmware.map { "connected, firmware \($0)" } ?? "connected")
  }
}
