import MacTouchKit
import MacTouchModel
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
  case overview, general, ring, fingers, monitors, smartCard, firmware, diagnostics

  var id: Self { self }

  var title: String {
    switch self {
    case .overview: return "MacTouch"
    case .general: return "General"
    case .ring: return "Ring"
    case .fingers: return "Fingers"
    case .monitors: return "Monitors"
    case .smartCard: return "Smart Card"
    case .firmware: return "Firmware"
    case .diagnostics: return "Diagnostics"
    }
  }

  var symbol: String {
    switch self {
    case .overview: return "touchid"
    case .general: return "gearshape.fill"
    case .ring: return "circle.circle"
    case .fingers: return "touchid"
    case .monitors: return "dot.radiowaves.left.and.right"
    case .smartCard: return "person.badge.key.fill"
    case .firmware: return "cpu.fill"
    case .diagnostics: return "stethoscope"
    }
  }

  var tint: Color {
    switch self {
    case .overview: return .gray
    case .general: return .gray
    case .ring: return .pink
    case .fingers: return .red
    case .monitors: return .orange
    case .smartCard: return .green
    case .firmware: return .blue
    case .diagnostics: return .indigo
    }
  }
}

/// The Settings window, laid out like System Settings: the device at the
/// top of a sidebar, the panes under it. The title follows the pane and the
/// last pane comes back next time, as the HIG asks. A menu bar app has no
/// main window, so opening this one also activates the app or the window
/// would land behind whatever is in front.
struct SettingsView: View {
  @ObservedObject var model: DaemonModel
  @ObservedObject var loginItem: LoginItem
  @AppStorage("settingsPane") private var pane: SettingsPane = .overview

  var body: some View {
    NavigationSplitView {
      List(selection: selection) {
        DeviceRow(model: model)
          .tag(SettingsPane.overview)
        Section {
          row(.general)
        }
        Section {
          row(.ring)
          row(.fingers)
          row(.monitors)
          row(.smartCard)
        }
        Section {
          row(.firmware)
          row(.diagnostics)
        }
      }
      .navigationSplitViewColumnWidth(230)
      .toolbar(removing: .sidebarToggle)
    } detail: {
      detail
        .navigationTitle(pane.title)
    }
    .frame(width: 715, height: 560)
    .onAppear { NSApp.activate(ignoringOtherApps: true) }
  }

  private func row(_ pane: SettingsPane) -> some View {
    Label { Text(pane.title) } icon: { SettingsIcon(symbol: pane.symbol, tint: pane.tint) }
      .tag(pane)
  }

  /// A List selection must be optional; clicking empty space never clears
  /// the pane.
  private var selection: Binding<SettingsPane?> {
    Binding(get: { pane }, set: { if let new = $0 { pane = new } })
  }

  @ViewBuilder private var detail: some View {
    switch pane {
    case .overview: OverviewPane(model: model, pane: $pane)
    case .general: GeneralPane(model: model, loginItem: loginItem)
    case .ring: RingPane(model: model)
    case .fingers: FingersPane(model: model)
    case .monitors: MonitorsPane(model: model)
    case .smartCard: SmartCardPane(model: model)
    case .firmware: FirmwarePane(model: model)
    case .diagnostics: DiagnosticsPane(model: model)
    }
  }
}

/// The sidebar's first row: the device with its ring live, like the
/// account at the top of System Settings.
struct DeviceRow: View {
  @ObservedObject var model: DaemonModel

  var body: some View {
    HStack(spacing: 10) {
      DeviceView(ring: model.deviceConnected ? model.ringState : .off, size: 32)
      VStack(alignment: .leading, spacing: 1) {
        Text("MacTouch")
          .font(.body.weight(.semibold))
        Text(model.connectionSummary)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 5)
  }
}

extension DaemonModel {
  var connectionSummary: String {
    guard daemonRunning else { return "Not running" }
    return deviceConnected ? "Connected" : "Not connected"
  }
}
