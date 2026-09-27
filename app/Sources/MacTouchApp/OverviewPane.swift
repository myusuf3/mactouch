import MacTouchKit
import MacTouchModel
import ServiceManagement
import SwiftUI

/// The first thing Settings shows: the sensor as it is right now, ring and
/// all, with the few facts worth a glance and a way into each.
struct OverviewPane: View {
  @ObservedObject var model: DaemonModel
  @Binding var pane: SettingsPane

  var body: some View {
    Form {
      Section {
        VStack(spacing: 12) {
          DeviceView(ring: ring, size: 148)
            .background(
              Circle()
                .fill((ring?.colour ?? .off).light)
                .blur(radius: 50)
                .opacity(ring == nil || ring?.mode == .off ? 0 : 0.35)
            )
            .padding(.top, 12)
            .padding(.bottom, 6)
          Text(headline)
            .font(.title.weight(.semibold))
          Text(subline)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)
          if !model.daemonRunning {
            Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
              .padding(.top, 4)
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 10)
      }
      if model.deviceConnected {
        Section {
          jump(to: .ring, title: "Ring", detail: ringDetail, value: model.ringState?.phrase ?? "")
          jump(to: .fingers, title: "Fingers", detail: "Approve sudo, scripts and agents with a touch", value: fingers)
          jump(to: .firmware, title: "Firmware", detail: model.firmwareUpdateAvailable ? "An update is ready to install" : "Up to date", value: model.firmware ?? "")
        }
      }
      Section {
      } footer: {
        AboutFooter()
      }
    }
    .formStyle(.grouped)
    .animation(.smooth, value: model.deviceConnected)
  }

  private var ring: RingState? {
    guard model.daemonRunning else { return nil }
    return model.deviceConnected ? model.ringState : .off
  }

  private var headline: String {
    guard model.daemonRunning else { return "MacTouch Is Not Running" }
    return model.deviceConnected ? "Ready When You Are" : "Plug In Your Sensor"
  }

  private var subline: String {
    guard model.daemonRunning else { return "Its background helper has stopped. Allow MacTouch under Login Items and it starts again." }
    guard model.deviceConnected else { return "Connect it with a USB-C cable that carries data. MacTouch finds it on its own." }
    return "Touch the sensor when your Mac asks. The ring tells you what your Mac is up to."
  }

  private var ringDetail: String {
    guard let owner = model.layers.last.flatMap(RingLayer.init(name:)), owner != .idle else { return "Resting in your colour" }
    return "Showing \(owner.title.lowercased())"
  }

  private var fingers: String {
    guard let prints = model.prints else { return "" }
    return prints == 1 ? "1 enrolled" : "\(prints) enrolled"
  }

  private func jump(to target: SettingsPane, title: String, detail: String, value: String) -> some View {
    Button { pane = target } label: {
      HStack {
        RowLabel(title: title, detail: detail, symbol: target.symbol, tint: target.tint)
        Spacer()
        Text(value)
          .foregroundStyle(.secondary)
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.tertiary)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// Version and credits, small and centred under the overview.
struct AboutFooter: View {
  private var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development build"
  }

  var body: some View {
    VStack(spacing: 4) {
      Text("MacTouch \(version)")
      HStack(spacing: 4) {
        Text("Hardware by")
        Link("tinytouch", destination: URL(string: "https://github.com/ZimengXiong/tinyTouch")!)
        Text("·")
        Link("Source on GitHub", destination: URL(string: "https://github.com/myusuf3/mactouch")!)
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .frame(maxWidth: .infinity)
    .padding(.top, 8)
  }
}
