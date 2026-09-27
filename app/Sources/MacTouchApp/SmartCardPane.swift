import AppKit
import MacTouchModel
import SwiftUI

/// Screen unlock through the device's smart card, docs/PIV.md, as three
/// steps that tick off from the card's own state. Everything here is also
/// `mactouch piv`; the PIN is changed with sc_auth, because macOS asks for
/// it in its own secure prompt.
struct SmartCardPane: View {
  @ObservedObject var model: DaemonModel
  @State private var confirmingReset = false
  @State private var confirmingPair = false

  var body: some View {
    Form {
      if let card = model.smartCard {
        Section {
          Toggle(isOn: enabled(card)) {
            RowLabel(title: "Smart Card", detail: card.encrypted ? "The sensor's flash is encrypted." : "Stays off on a sensor whose flash is not encrypted.",
                     symbol: "creditcard.fill", tint: .green)
          }
          .disabled(!card.encrypted && !card.enabled || model.smartCardAction != nil)
        } footer: {
          Footnote("Unlock your Mac with the sensor: at the lock screen, type the card's PIN, then touch.")
        }
        Section {
          step(1, "Create Keys", done: card.identity,
               detail: card.identity ? "Made on the sensor. They never leave it." : "Made on the sensor with a touch.") {
            if !card.identity {
              Button("Create…") { model.generateSmartCardIdentity() }
                .disabled(!card.enabled || model.smartCardAction != nil)
            }
          }
          step(2, "Choose a PIN", done: card.identity && !card.pinIsDefault,
               detail: card.pinIsDefault ? "Run sc_auth changepin in Terminal. Six to eight digits." : "Set, \(card.retries) tries left.") {
            if card.pinIsDefault {
              Button("Copy Command") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("sc_auth changepin", forType: .string)
              }
              .disabled(!card.identity)
            }
          }
          step(3, "Pair with Your Account", done: card.paired == true, detail: pairingText(card)) {
            if card.paired == true {
              Button("Unpair") { model.unpairSmartCard() }
                .disabled(model.smartCardAction != nil)
            } else {
              Button("Pair…") { confirmingPair = true }
                .disabled(!card.identity || card.pinIsDefault || card.unpairedHash == nil || model.smartCardAction != nil)
            }
          }
          if let action = model.smartCardAction {
            HStack(spacing: 8) {
              ProgressView().controlSize(.small)
              Text(progress(action)).foregroundStyle(.secondary)
            }
          } else if let error = model.smartCardError {
            Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
          }
        } header: {
          Text("Setup")
        } footer: {
          Footnote("Keep your password and a second admin account, and never turn on smart card enforcement.")
        }
        if card.identity {
          Section {
            Button("Reset Card…", role: .destructive) { confirmingReset = true }
              .disabled(model.smartCardAction != nil)
          }
        }
      } else {
        Section {
          Text(model.deviceConnected ? "Reading the card…" : "Connect the sensor to see its smart card.")
            .foregroundStyle(.secondary)
        }
      }
    }
    .formStyle(.grouped)
    .onAppear { model.refreshSmartCard() }
    .confirmationDialog("Pair the smart card with your account?", isPresented: $confirmingPair, titleVisibility: .visible) {
      Button("Pair") { model.pairSmartCard() }
    } message: {
      Text("The lock screen will accept the card's PIN and a touch. Keep your password and a second admin account, and never turn on smart card enforcement.")
    }
    .confirmationDialog("Reset the smart card?", isPresented: $confirmingReset, titleVisibility: .visible) {
      Button("Reset Card", role: .destructive) { model.resetSmartCard() }
    } message: {
      Text("The keys are destroyed and the PIN returns to 123456. Any pairing stops working; unpair first to keep your account tidy.")
    }
  }

  private func step<Action: View>(_ number: Int, _ title: String, done: Bool, detail: String, @ViewBuilder action: () -> Action) -> some View {
    HStack(spacing: 12) {
      ZStack {
        Circle()
          .fill(done ? AnyShapeStyle(Color.green.gradient) : AnyShapeStyle(.quaternary))
        if done {
          Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
        } else {
          Text("\(number)").font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(.secondary)
        }
      }
      .frame(width: 24, height: 24)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      action()
    }
    .animation(.spring(duration: 0.4), value: done)
  }

  private func enabled(_ card: DaemonModel.SmartCard) -> Binding<Bool> {
    Binding(get: { card.enabled }, set: { model.setSmartCard(enabled: $0) })
  }

  private func pairingText(_ card: DaemonModel.SmartCard) -> String {
    guard card.identity else { return "Needs keys first." }
    switch card.paired {
    case true?: return "The lock screen accepts the card."
    case false?: return card.pinIsDefault ? "Needs a PIN of your own first." : "Asks for an administrator, then your password and PIN."
    case nil: return "Could not ask macOS about pairing."
    }
  }

  private func progress(_ action: String) -> String {
    switch action {
    case "genkey": return "Touch the sensor to make the keys…"
    case "reset": return "Touch the sensor to reset the card…"
    case "pair": return "Follow the macOS prompts: administrator, then password and PIN…"
    default: return "Unpairing…"
    }
  }
}
