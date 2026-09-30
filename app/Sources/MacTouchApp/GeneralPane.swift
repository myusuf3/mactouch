import MacTouchKit
import MacTouchModel
import ServiceManagement
import SwiftUI

struct GeneralPane: View {
  @ObservedObject var model: DaemonModel
  @ObservedObject var loginItem: LoginItem
  @AppStorage(showInMenuBarKey) private var showInMenuBar = true

  var body: some View {
    Form {
      Section {
        SensorCard(model: model)
      }
      Section {
        Toggle("Launch at login", isOn: launchAtLogin)
        if loginItem.status == .requiresApproval {
          LabeledContent("Waiting for approval under Login Items") {
            Button("Open Login Items…") { loginItem.openLoginItems() }
          }
        }
        if let error = loginItem.lastError {
          Text(error).foregroundStyle(.red)
        }
        Toggle("Show in menu bar", isOn: $showInMenuBar)
      } footer: {
        Footnote("Without the icon, MacTouch keeps running and still shows fingerprint requests. Open MacTouch again to bring the icon back.")
      }
      if let tool = model.commandLineTool {
        CommandLineSection(model: model, tool: tool)
      }
    }
    .formStyle(.grouped)
    .onAppear {
      loginItem.refresh()
      model.refreshInstallState()
    }
  }

  private var launchAtLogin: Binding<Bool> {
    Binding(get: { loginItem.isEnabled }, set: { loginItem.set(enabled: $0) })
  }
}

/// The sensor at a glance: lit as it is on the desk, with what is worth
/// knowing about it on one line.
struct SensorCard: View {
  @ObservedObject var model: DaemonModel

  var body: some View {
    HStack(spacing: 14) {
      DeviceView(ring: ring, size: 56)
      VStack(alignment: .leading, spacing: 3) {
        Text("MacTouch Sensor")
          .font(.headline)
        Text(summary)
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      Spacer()
      if model.daemonRunning {
        StatusBadge(text: model.deviceConnected ? "Connected" : "Not connected", tint: model.deviceConnected ? .green : .secondary)
      } else {
        Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
      }
    }
    .padding(.vertical, 6)
    .animation(.smooth, value: model.deviceConnected)
  }

  private var ring: RingState? {
    guard model.daemonRunning else { return nil }
    return model.deviceConnected ? model.ringState : .off
  }

  private var summary: String {
    guard model.daemonRunning else { return "The background helper has stopped. Allow MacTouch under Login Items." }
    guard model.deviceConnected else { return "Plug it in with a USB-C cable that carries data." }
    var parts: [String] = []
    if let firmware = model.firmware { parts.append("Firmware \(firmware)") }
    if let prints = model.prints { parts.append(prints == 1 ? "1 finger" : "\(prints) fingers") }
    return parts.isEmpty ? "Ready" : parts.joined(separator: " · ")
  }
}

/// The `mactouch` command in /usr/local/bin, which is on every Mac's PATH,
/// linked to this copy of the app behind the administrator prompt.
struct CommandLineSection: View {
  @ObservedObject var model: DaemonModel
  var tool: CommandLineTool

  var body: some View {
    Section {
      HStack {
        RowLabel(title: "Command line tool", detail: detail, symbol: "apple.terminal.fill", tint: .gray)
        Spacer()
        switch tool {
        case .installed: Button("Remove…") { model.removeCommandLineTool() }.disabled(busy)
        case .stale: Button("Update…") { model.installCommandLineTool() }.disabled(busy)
        case .absent: Button("Install…") { model.installCommandLineTool() }.disabled(busy)
        case .occupied: EmptyView()
        }
      }
      if busy {
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text("Enter your password in the macOS prompt…").foregroundStyle(.secondary)
        }
      } else if case .failed(let reason)? = model.commandLineTask, reason != "cancelled" {
        Label(reason, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
      }
    } footer: {
      Footnote("Everything the app does, mactouch does in Terminal too, and scripts and agents can call it.")
    }
  }

  private var busy: Bool { model.commandLineTask == .running }

  private var detail: String {
    switch tool {
    case .installed: return "mactouch is in /usr/local/bin."
    case .stale: return "/usr/local/bin/mactouch points at another copy of MacTouch."
    case .absent: return "Put mactouch in /usr/local/bin, on every terminal's PATH."
    case .occupied: return "Something else is at /usr/local/bin/mactouch; MacTouch leaves it alone."
    }
  }
}
