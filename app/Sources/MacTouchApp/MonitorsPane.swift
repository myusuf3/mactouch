import MacTouchKit
import MacTouchModel
import SwiftUI

extension MonitorName {
  var symbol: String {
    switch self {
    case .lock: return "lock.fill"
    case .mic: return "mic.fill"
    case .camera: return "video.fill"
    }
  }

  var tint: Color {
    switch self {
    case .lock: return .blue
    case .mic: return .orange
    case .camera: return .green
    }
  }

  var detail: String {
    switch self {
    case .lock: return "Turns the ring off while your Mac is locked."
    case .mic: return "Breathes red while an app is listening."
    case .camera: return "Breathes red while the camera is on."
    }
  }
}

struct MonitorsPane: View {
  @ObservedObject var model: DaemonModel

  var body: some View {
    Form {
      Section {
        ForEach(MonitorName.allCases, id: \.self) { name in
          Toggle(isOn: monitor(name)) {
            RowLabel(title: name.label, detail: name.detail, symbol: name.symbol, tint: name.tint)
          }
        }
      } footer: {
        Footnote("MacTouch watches these on your Mac and shows them on the ring, so you know at a glance.")
      }
      .disabled(!model.daemonRunning)
    }
    .formStyle(.grouped)
  }

  private func monitor(_ name: MonitorName) -> Binding<Bool> {
    Binding(get: { model.monitors.contains(name) }, set: { model.setMonitor(name, enabled: $0) })
  }
}
