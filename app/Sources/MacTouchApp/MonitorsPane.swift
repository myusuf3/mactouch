import AppKit
import MacTouchKit
import MacTouchModel
import SwiftUI

extension MonitorName {
  var symbol: String {
    switch self {
    case .lock: return "lock.fill"
    case .focus: return "moon.fill"
    case .mic: return "mic.fill"
    case .camera: return "video.fill"
    }
  }

  var tint: Color {
    switch self {
    case .lock: return .blue
    case .focus: return .indigo
    case .mic: return .orange
    case .camera: return .green
    }
  }

  var detail: String {
    switch self {
    case .lock: return "Turns the ring off while your Mac is locked."
    case .focus: return "Glows magenta while a Focus is on."
    case .mic: return "Breathes red while an app is listening."
    case .camera: return "Breathes red while the camera is on."
    }
  }
}

struct MonitorsPane: View {
  @ObservedObject var model: DaemonModel

  var body: some View {
    Form {
      PaneHeader(.monitors, summary: "MacTouch watches a few things on your Mac and shows them on the ring, so you know at a glance.")
      Section {
        ForEach(MonitorName.allCases, id: \.self) { name in
          Toggle(isOn: monitor(name)) {
            RowLabel(title: name.label, detail: name.detail, symbol: name.symbol, tint: name.tint)
          }
        }
      }
      .disabled(!model.daemonRunning)
      if model.monitors.contains(.focus), model.focusSource == .menubar {
        Section {
          HStack {
            RowLabel(title: "Give MacTouch Full Disk Access",
                     detail: "Focus is read from the menu bar until mactouchd can read the Focus store, which misses some modes.",
                     symbol: "externaldrive.fill.badge.checkmark", tint: .gray)
            Spacer()
            Button("Open Settings…") {
              NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
          }
        }
      }
    }
    .formStyle(.grouped)
  }

  private func monitor(_ name: MonitorName) -> Binding<Bool> {
    Binding(get: { model.monitors.contains(name) }, set: { model.setMonitor(name, enabled: $0) })
  }
}
