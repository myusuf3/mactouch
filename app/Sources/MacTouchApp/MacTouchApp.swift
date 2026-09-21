import MacTouchKit
import MacTouchModel
import SwiftUI

/// The menu bar app: a view over mactouchd, one more client of its socket.
/// A plain menu, as the HIG asks of menu bar extras; the `touchid` symbol is
/// a template image so the system colours it for light and dark menu bars.
@main
struct MacTouchApp: App {
  @StateObject private var model: DaemonModel
  @StateObject private var loginItem = LoginItem()
  @NSApplicationDelegateAdaptor private var delegate: AppDelegate
  /// The HIG leaves it to people whether an extra sits in their menu bar.
  /// The app keeps running hidden; opening it again brings the icon back.
  @AppStorage(showInMenuBarKey) private var showInMenuBar = true
  private let requestPanel: RequestPanel

  init() {
    let model = DaemonModel()
    _model = StateObject(wrappedValue: model)
    requestPanel = RequestPanel(model: model)
  }

  var body: some Scene {
    MenuBarExtra("MacTouch", systemImage: "touchid", isInserted: $showInMenuBar) {
      StatusMenu(model: model)
    }
    Settings {
      SettingsView(model: model, loginItem: loginItem)
    }
  }
}

let showInMenuBarKey = "showInMenuBar"

final class AppDelegate: NSObject, NSApplicationDelegate {
  /// Opening the app while it already runs, from Finder or Spotlight, is the
  /// way back once the menu bar icon has been hidden.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    UserDefaults.standard.set(true, forKey: showInMenuBarKey)
    return true
  }
}

struct StatusMenu: View {
  @ObservedObject var model: DaemonModel

  var body: some View {
    Text(statusLine)
    if let ringLine { Text(ringLine) }
    if !model.daemonRunning {
      Button("Start Daemon") { model.startDaemon() }
    }
    Divider()
    if model.daemonRunning {
      Picker("Idle Colour", selection: idleColour) {
        ForEach(LEDColour.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
      }
      .pickerStyle(.menu)
      .disabled(!model.deviceConnected)
      Menu("Monitors") {
        ForEach(MonitorName.allCases, id: \.self) { name in
          Toggle(name.label, isOn: monitor(name))
        }
      }
      if model.notifyActive {
        Button("Clear Notify Layer") { model.clearNotify() }
      }
      Divider()
    }
    SettingsLink { Text("Settings…") }
      .keyboardShortcut(",")
    Button("Quit MacTouch") { NSApplication.shared.terminate(nil) }
      .keyboardShortcut("q")
  }

  private var idleColour: Binding<LEDColour> {
    Binding(get: { model.idle ?? .off }, set: { model.setIdle($0) })
  }

  private func monitor(_ name: MonitorName) -> Binding<Bool> {
    Binding(get: { model.monitors.contains(name) }, set: { model.setMonitor(name, enabled: $0) })
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
