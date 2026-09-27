import MacTouchModel
import SwiftUI

/// The sensor's firmware against the image this app carries, and the update
/// over the link (ADR-0018): the sensor, the versions, and one button.
struct FirmwarePane: View {
  @ObservedObject var model: DaemonModel

  var body: some View {
    Form {
      Section {
        VStack(spacing: 14) {
          DeviceHero(ring: model.deviceConnected ? model.ringState : .off, size: 96)
          if let versions {
            VersionCapsule(text: versions)
          }
          VStack(spacing: 3) {
            Text(headline)
              .font(.title3.weight(.semibold))
            Text(subline)
              .font(.callout)
              .foregroundStyle(.secondary)
          }
          if let progress = model.firmwareProgress {
            VStack(spacing: 8) {
              if case .writing(let fraction) = progress {
                ProgressView(value: fraction)
              } else if model.firmwareUpdating {
                ProgressView().progressViewStyle(.linear)
              }
              Label(text(progress), systemImage: symbol(progress))
                .font(.callout)
                .foregroundStyle(colour(progress))
            }
            .frame(maxWidth: 320)
          }
          if model.firmwareUpdateAvailable || model.firmwareUpdating {
            Button { model.updateFirmware() } label: {
              Text("Install").frame(width: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.firmwareUpdating)
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
      }
      Section {
        DisclosureGroup {
          Text("It travels over USB once you touch the sensor, and lands in the spare slot. The sensor switches to it on the next start.")
            .foregroundStyle(.secondary)
        } label: {
          Label { Text("How Updates Work") } icon: { SettingsIcon(symbol: "arrow.down", tint: .blue, size: 22) }
        }
        DisclosureGroup {
          Text("New firmware has to confirm itself once it is up and talking to your Mac. If it does not, the sensor goes back to the version it had, on its own.")
            .foregroundStyle(.secondary)
        } label: {
          Label { Text("If Something Goes Wrong") } icon: { SettingsIcon(symbol: "arrow.uturn.backward", tint: .orange, size: 22) }
        }
      }
      Section {
        LabeledContent("On the sensor", value: board)
        LabeledContent("Included with MacTouch", value: model.bundledFirmware?.version ?? "None")
      }
    }
    .formStyle(.grouped)
    .animation(.smooth, value: model.firmwareProgress)
  }

  /// "0.2.2" or, with an update waiting, "0.2.2 → 0.2.3".
  private var versions: String? {
    guard model.deviceConnected, let firmware = model.firmware else { return nil }
    guard model.firmwareUpdateAvailable, let carried = model.bundledFirmware?.version else { return firmware }
    return "\(firmware) → \(carried)"
  }

  private var headline: String {
    guard model.deviceConnected, model.firmware != nil else { return "Sensor Not Connected" }
    if model.bundledFirmware == nil { return "No Update Included" }
    return model.firmwareUpdateAvailable ? "An Update Is Ready" : "Up to Date"
  }

  private var subline: String {
    guard model.deviceConnected else { return "Connect the sensor to check its firmware." }
    if model.firmwareUpdateAvailable { return "Install it with a touch. It takes about twenty seconds." }
    return model.bundledFirmware == nil ? "This copy of MacTouch carries no firmware to install." : "There is nothing newer to install."
  }

  private var board: String {
    guard model.deviceConnected, let firmware = model.firmware else { return "Not connected" }
    return model.slot.map { "\(firmware) (\($0))" } ?? firmware
  }

  private func text(_ progress: DaemonModel.FirmwareProgress) -> String {
    switch progress {
    case .waitingForTouch: return "Touch the sensor to allow the update"
    case .writing: return "Writing firmware…"
    case .installing: return "Checking and installing; the sensor restarts"
    case .confirming: return "Waiting for the new firmware to confirm itself…"
    case .done(let version): return "Updated to \(version)"
    case .failed(let reason): return reason
    }
  }

  private func symbol(_ progress: DaemonModel.FirmwareProgress) -> String {
    switch progress {
    case .waitingForTouch: return "touchid"
    case .done: return "checkmark.circle.fill"
    case .failed: return "exclamationmark.triangle.fill"
    default: return "arrow.down.circle"
    }
  }

  private func colour(_ progress: DaemonModel.FirmwareProgress) -> Color {
    switch progress {
    case .done: return .green
    case .failed: return .red
    default: return .secondary
    }
  }
}
