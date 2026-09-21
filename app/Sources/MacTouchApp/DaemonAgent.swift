import Foundation
import ServiceManagement

/// The daemon's launch agent, the plist inside this bundle that names
/// `mactouchd` next to the app. Registering it through SMAppService starts
/// the daemon and lists MacTouch under Login Items; the app does so on every
/// launch so launchd always points at the copy of the app that is running.
final class DaemonAgent: ObservableObject {
  static let label = "dev.mactouch.daemon"
  private let service = SMAppService.agent(plistName: "\(DaemonAgent.label).plist")
  @Published private(set) var status: SMAppService.Status
  @Published private(set) var lastError: String?

  init() {
    status = service.status
  }

  func install() {
    retireLegacyAgent()
    register()
  }

  func register() {
    do {
      try service.register()
      lastError = nil
    } catch {
      lastError = error.localizedDescription
      NSLog("daemon agent: %@", error.localizedDescription)
    }
    refresh()
  }

  func refresh() {
    status = service.status
  }

  func openLoginItems() {
    SMAppService.openSystemSettingsLoginItems()
  }

  /// scripts/install.sh wrote a plist with the same label to
  /// ~/Library/LaunchAgents. Two agents cannot share a label, so the app
  /// takes over: unload it and remove it. install.sh is the path for a
  /// checkout without the app from here on.
  private func retireLegacyAgent() {
    let plist = NSHomeDirectory() + "/Library/LaunchAgents/\(Self.label).plist"
    guard FileManager.default.fileExists(atPath: plist) else { return }
    let bootout = Process()
    bootout.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    bootout.arguments = ["bootout", "gui/\(getuid())/\(Self.label)"]
    bootout.standardError = FileHandle.nullDevice
    try? bootout.run()
    bootout.waitUntilExit()
    try? FileManager.default.removeItem(atPath: plist)
    NSLog("daemon agent: retired the install.sh launch agent, the bundled one takes over")
  }
}
