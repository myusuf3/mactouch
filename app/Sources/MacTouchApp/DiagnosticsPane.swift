import MacTouchKit
import MacTouchModel
import SwiftUI

/// The rows of `mactouch doctor`, from the same `HealthReport`.
struct DiagnosticsPane: View {
  @ObservedObject var model: DaemonModel

  var body: some View {
    Form {
      Section {
        if let health = model.health {
          ForEach(health.checks, id: \.name) { check in
            LabeledContent {
              Text(check.detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
            } label: {
              HStack(spacing: 10) {
                Image(systemName: symbol(check.verdict))
                  .foregroundStyle(colour(check.verdict))
                  .frame(width: 18)
                Text(check.name.capitalized)
              }
            }
          }
        } else {
          HStack {
            ProgressView().controlSize(.small)
            Text("Checking…").foregroundStyle(.secondary)
          }
        }
      } header: {
        Text(summary)
      } footer: {
        Footnote("The same check-up as mactouch doctor, including the sensor's self-test.")
      }
      Section {
        Button("Check Again") { model.refreshHealth() }
      }
    }
    .formStyle(.grouped)
    .onAppear { model.refreshHealth() }
    .onChange(of: model.deviceConnected) { model.refreshHealth() }
  }

  private var summary: String {
    guard let checks = model.health?.checks else { return "Checking" }
    let problems = checks.filter { $0.verdict == .warn || $0.verdict == .bad }.count
    switch problems {
    case 0: return "Everything Checks Out"
    case 1: return "One Thing Needs a Look"
    default: return "\(problems) Things Need a Look"
    }
  }

  private func symbol(_ verdict: HealthCheck.Verdict) -> String {
    switch verdict {
    case .ok: return "checkmark.circle.fill"
    case .warn: return "exclamationmark.triangle.fill"
    case .bad: return "xmark.octagon.fill"
    case .off: return "minus.circle"
    }
  }

  private func colour(_ verdict: HealthCheck.Verdict) -> Color {
    switch verdict {
    case .ok: return .green
    case .warn: return .orange
    case .bad: return .red
    case .off: return .secondary
    }
  }
}
