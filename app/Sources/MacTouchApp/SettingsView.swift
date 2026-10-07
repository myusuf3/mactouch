import MacTouchKit
import MacTouchModel
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
  case general, ring, monitors, fingers, smartCard, passwords, firmware, diagnostics, about

  var id: Self { self }

  var title: String {
    switch self {
    case .general: return "General"
    case .ring: return "Ring"
    case .monitors: return "Monitors"
    case .fingers: return "Fingers"
    case .smartCard: return "Smart Card"
    case .passwords: return "Passwords"
    case .firmware: return "Firmware"
    case .diagnostics: return "Diagnostics"
    case .about: return "About"
    }
  }

  var symbol: String {
    switch self {
    case .general: return "gearshape.fill"
    case .ring: return "circle.circle"
    case .monitors: return "dot.radiowaves.left.and.right"
    case .fingers: return "touchid"
    case .smartCard: return "person.badge.key.fill"
    case .passwords: return "key.fill"
    case .firmware: return "cpu.fill"
    case .diagnostics: return "stethoscope"
    case .about: return "info"
    }
  }

  var tint: Color {
    switch self {
    case .general: return .gray
    case .ring: return .pink
    case .monitors: return .orange
    case .fingers: return .red
    case .smartCard: return .green
    case .passwords: return .orange
    case .firmware: return .blue
    case .diagnostics: return .indigo
    case .about: return .gray
    }
  }
}

/// The Settings window: General on its own, then the panes grouped under
/// headers in the sidebar, and the pane's icon and name in the title bar
/// rather than a banner, so each pane starts with its settings. The last
/// pane comes back next time, as the HIG asks. A menu bar app has no main
/// window, so opening this one also activates the app or the window would
/// land behind whatever is in front.
struct SettingsView: View {
  @ObservedObject var model: DaemonModel
  @ObservedObject var loginItem: LoginItem
  @AppStorage("settingsPane") private var pane: SettingsPane = .general

  var body: some View {
    NavigationSplitView {
      List(selection: selection) {
        row(.general)
        Section("Light") {
          row(.ring)
          row(.monitors)
        }
        Section("Security") {
          row(.fingers)
          row(.smartCard)
          row(.passwords)
        }
        Section("MacTouch") {
          row(.firmware)
          row(.diagnostics)
          row(.about)
        }
      }
      .navigationSplitViewColumnWidth(210)
      .toolbar(removing: .sidebarToggle)
    } detail: {
      detail
        .paneTitle(pane)
    }
    .tint(model.idle?.accent)
    .frame(width: 700, height: 600)
    .onAppear { NSApp.activate(ignoringOtherApps: true) }
  }

  private func row(_ pane: SettingsPane) -> some View {
    Label { Text(pane.title) } icon: { SettingsIcon(symbol: pane.symbol, tint: pane.tint, size: 22) }
      .padding(.vertical, 2)
      .tag(pane)
  }

  /// A List selection must be optional; clicking empty space never clears
  /// the pane.
  private var selection: Binding<SettingsPane?> {
    Binding(get: { pane }, set: { if let new = $0 { pane = new } })
  }

  @ViewBuilder private var detail: some View {
    switch pane {
    case .general: GeneralPane(model: model, loginItem: loginItem)
    case .ring: RingPane(model: model)
    case .monitors: MonitorsPane(model: model)
    case .fingers: FingersPane(model: model)
    case .smartCard: SmartCardPane(model: model)
    case .passwords: PasswordsPane(model: model)
    case .firmware: FirmwarePane(model: model)
    case .diagnostics: DiagnosticsPane(model: model)
    case .about: AboutPane(model: model)
    }
  }
}

extension LEDColour {
  /// The ring's colour as the window's tint, so toggles and selections
  /// match the sensor. Off and white have no hue to lend, and yellow is
  /// too light to carry white text, so those keep the system accent.
  var accent: Color? {
    switch self {
    case .off, .white, .yellow: return nil
    default: return light
    }
  }
}

private extension View {
  /// The pane's icon and name in the title bar, where the window title
  /// would sit. The title stays the window's, for the Window menu and
  /// Mission Control; before macOS 15 it cannot be hidden, so it shows.
  @ViewBuilder func paneTitle(_ pane: SettingsPane) -> some View {
    if #available(macOS 15.0, *) {
      navigationTitle(pane.title)
        .toolbar(removing: .title)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbar {
          ToolbarItem(placement: .navigation) {
            HStack(spacing: 8) {
              SettingsIcon(symbol: pane.symbol, tint: pane.tint, size: 24)
              Text(pane.title)
                .font(.title3.weight(.semibold))
            }
          }
        }
    } else {
      navigationTitle(pane.title)
    }
  }
}
