import MacTouchModel
import SwiftUI

/// The sensor's firmware against the image this app carries, and the update
/// over the link (ADR-0018), laid out like Software Update.
struct FirmwarePane: View {
  @ObservedObject var model: DaemonModel

  var body: some View {
    Form {
      Section {
        HStack(alignment: .center, spacing: 14) {
          SettingsIcon(symbol: SettingsPane.firmware.symbol, tint: SettingsPane.firmware.tint, size: 52)
          VStack(alignment: .leading, spacing: 3) {
            Text(headline)
              .font(.headline)
            Text(subline)
              .font(.callout)
              .foregroundStyle(.secondary)
          }
          Spacer()
          if model.firmwareUpdateAvailable || model.firmwareUpdating {
            Button("Update Now") { model.updateFirmware() }
              .buttonStyle(.borderedProminent)
              .disabled(model.firmwareUpdating)
          }
        }
        .padding(.vertical, 6)
        if let progress = model.firmwareProgress {
          VStack(alignment: .leading, spacing: 6) {
            if case .writing(let fraction) = progress {
              ProgressView(value: fraction)
            } else if model.firmwareUpdating {
              ProgressView().progressViewStyle(.linear)
            }
            Label(text(progress), systemImage: symbol(progress))
              .font(.callout)
              .foregroundStyle(colour(progress))
          }
        }
      } footer: {
        Footnote("Updates install over USB after a touch. If new firmware fails to start, the sensor goes back to the old one on its own.")
      }
      Section {
        LabeledContent("On the sensor", value: board)
        LabeledContent("Included with MacTouch", value: model.bundledFirmware?.version ?? "None")
      }
    }
    .formStyle(.grouped)
    .animation(.smooth, value: model.firmwareProgress)
  }

  private var headline: String {
    guard model.deviceConnected, let firmware = model.firmware else { return "Sensor Not Connected" }
    if model.firmwareUpdateAvailable, let version = model.bundledFirmware?.version { return "Firmware \(version) Is Available" }
    return "Firmware \(firmware)"
  }

  private var subline: String {
    guard model.deviceConnected else { return "Connect the sensor to check its firmware." }
    if model.firmwareUpdateAvailable { return "Your sensor runs \(model.firmware ?? "an older version")." }
    return "Your sensor is up to date."
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
