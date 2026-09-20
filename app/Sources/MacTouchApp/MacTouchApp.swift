import MacTouchKit
import SwiftUI

/// The menu bar app: a view over mactouchd, one more client of its socket.
/// A plain menu, as the HIG asks of menu bar extras; the `touchid` symbol is
/// a template image so the system colours it for light and dark menu bars.
@main
struct MacTouchApp: App {
  @StateObject private var model = DaemonModel()

  var body: some Scene {
    MenuBarExtra("MacTouch", systemImage: "touchid") {
      StatusMenu(model: model)
    }
  }
}

struct StatusMenu: View {
  @ObservedObject var model: DaemonModel

  var body: some View {
    Text(statusLine)
    if let ringLine { Text(ringLine) }
    Divider()
    Button("Quit MacTouch") { NSApplication.shared.terminate(nil) }
      .keyboardShortcut("q")
  }

  private var statusLine: String {
    guard model.daemonRunning else { return "Daemon not running" }
    guard model.deviceConnected else { return "Device not connected" }
    var parts = ["Connected"]
    if let sensor = model.sensor { parts.append("sensor \(sensor)") }
    if let prints = model.prints { parts.append(prints == 1 ? "1 finger" : "\(prints) fingers") }
    return parts.joined(separator: " · ")
  }

  /// "Ring: breathing red (privacy)". The owning layer is named unless it is
  /// the idle colour, which needs no explanation.
  private var ringLine: String? {
    guard model.daemonRunning, model.deviceConnected, let ring = model.ring else { return nil }
    let parts = ring.split(separator: ":").map(String.init)
    guard let mode = parts.first.flatMap(LEDMode.init), mode != .off, parts.count >= 2 else { return "Ring: off" }
    let colours = parts.dropFirst().joined(separator: " and ")
    var line = "Ring: \(describe(mode)) \(colours)"
    if let owner = model.layers.last, owner != "idle" { line += " (\(owner))" }
    return line
  }

  private func describe(_ mode: LEDMode) -> String {
    switch mode {
    case .off: return "off"
    case .on: return "steady"
    case .breathe: return "breathing"
    case .flash: return "flashing"
    case .fadein: return "fading in"
    case .fadeout: return "fading out"
    }
  }
}
