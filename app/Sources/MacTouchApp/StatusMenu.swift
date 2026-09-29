import MacTouchKit
import MacTouchModel
import SwiftUI

let showInMenuBarKey = "showInMenuBar"

/// The menu bar extra's menu: a plain menu, as the HIG asks. State first,
/// with a dot in the ring's own colour, then the few things reached for
/// often, then Settings and Quit.
struct StatusMenu: View {
  @ObservedObject var model: DaemonModel
  @ObservedObject var agent: DaemonAgent
  var openSetup: () -> Void

  var body: some View {
    Label { Text(statusLine) } icon: { Image(nsImage: (model.deviceConnected ? model.ringState?.colour : nil)?.swatch ?? LEDColour.off.swatch) }
      .onAppear { agent.refresh() }
    if let ringLine { Text(ringLine) }
    if !model.daemonRunning {
      if agent.status == .requiresApproval {
        Button("Allow MacTouch in Login Items…") { agent.openLoginItems() }
      } else {
        Button("Start Daemon") { agent.register() }
      }
    }
    if model.daemonRunning {
      Divider()
      Picker("Ring Colour", selection: idleColour) {
        ForEach(LEDColour.allCases, id: \.self) { colour in
          Label { Text(colour.name) } icon: { Image(nsImage: colour.swatch) }.tag(colour)
        }
      }
      .pickerStyle(.menu)
      .disabled(!model.deviceConnected)
      Section("Monitors") {
        ForEach(MonitorName.allCases, id: \.self) { name in
          Toggle(name.label, isOn: monitor(name))
        }
      }
      if model.notifyActive || model.firmwareUpdating || model.firmwareUpdateAvailable {
        Divider()
      }
      if model.notifyActive {
        Button("Clear Notification Light") { model.clearNotify() }
      }
      if model.firmwareUpdating {
        Text("Updating Firmware…")
      } else if model.firmwareUpdateAvailable, let version = model.bundledFirmware?.version {
        Button("Update Firmware to \(version)…") { model.updateFirmware() }
      }
    }
    Divider()
    Button("Set Up MacTouch…", action: openSetup)
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
    guard model.daemonRunning else { return "Daemon Not Running" }
    guard model.deviceConnected else { return "Sensor Not Connected" }
    guard let prints = model.prints else { return "Connected" }
    return prints == 1 ? "Connected · 1 Finger" : "Connected · \(prints) Fingers"
  }

  /// "Privacy · Breathing Red", only while a layer covers the resting
  /// colour; the dot beside the status line already shows that one.
  private var ringLine: String? {
    guard model.daemonRunning, model.deviceConnected, let ring = model.ringState else { return nil }
    guard let owner = model.layers.last.flatMap(RingLayer.init(name:)), owner != .idle else { return nil }
    return "\(owner.title) · \(ring.title)"
  }
}

extension RingLayer {
  init?(name: String) {
    guard let layer = Self.allCases.first(where: { $0.name == name }) else { return nil }
    self = layer
  }

  var title: String {
    switch self {
    case .idle: return "Resting"
    case .locked: return "Screen Locked"
    case .privacy: return "Privacy"
    case .notify: return "Notification"
    case .prompt: return "Fingerprint Request"
    }
  }

  var symbol: String {
    switch self {
    case .idle: return "circle.fill"
    case .locked: return "lock.fill"
    case .privacy: return "mic.fill"
    case .notify: return "bell.badge.fill"
    case .prompt: return "touchid"
    }
  }

  /// What the ring shows while this layer is on top, as the daemon and
  /// firmware set it.
  var sample: RingState {
    switch self {
    case .idle: return RingState(.on, .cyan)
    case .locked: return .off
    case .privacy: return RingState(.breathe, .red)
    case .notify: return RingState(.breathe, .yellow)
    case .prompt: return RingState(.breathe, .blue)
    }
  }

  var explanation: String {
    switch self {
    case .idle: return "Your chosen colour, whenever nothing else needs the ring."
    case .locked: return "Dark while your Mac is locked."
    case .privacy: return "Breathes red while the microphone or camera is live."
    case .notify: return "Breathes in the colour a script or agent picks."
    case .prompt: return "Breathes blue when an app asks, white for sudo."
    }
  }
}
