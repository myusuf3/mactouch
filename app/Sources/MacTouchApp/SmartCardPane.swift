import AppKit
import MacTouchKit
import MacTouchModel
import SwiftUI

/// Unlocking the Mac: the device's smart card, docs/PIV.md, or the password
/// the sensor types after a touch, ADR-0022. Everything here is also
/// `mactouch piv` and `mactouch password`; the PIN is changed with sc_auth,
/// because macOS asks for it in its own secure prompt.
struct SmartCardPane: View {
  @ObservedObject var model: DaemonModel
  @State private var confirmingReset = false
  /// The password sheet, and whether saving switches to password mode.
  @State private var editingPassword: Bool?

  var body: some View {
    Form {
      if let card = model.smartCard {
        Section {
          Picker(selection: unlockMode(card)) {
            Text("PIN and Touch").tag(UnlockMode.pin)
            Text("Password").tag(UnlockMode.password)
          } label: {
            RowLabel(title: "Unlock With",
                     detail: card.unlockMode == .password ? "A touch types your password." : "The smart card's PIN, then a touch.",
                     symbol: "lock.open.fill", tint: .blue)
          }
          .pickerStyle(.menu)
          .disabled(model.smartCardAction != nil || card.passwordStored == nil)
          if card.unlockMode == .password {
            passwordRow(stored: card.passwordStored == true)
          }
        } footer: {
          Footnote(card.unlockMode == .password
                   ? "When a password field asks, at the lock screen or in any app, the ring breathes white. Touch the sensor and it types your password. After a restart, type it once at the login window."
                   : "Unlock your Mac with the sensor: at the lock screen, type the card's PIN, then touch.")
        }
        if card.unlockMode == .pin {
          pinSections(card)
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
    .sheet(isPresented: Binding(get: { editingPassword != nil }, set: { if !$0 { editingPassword = nil } })) {
      PasswordSheet(model: model, thenUse: editingPassword ?? false)
    }
    .confirmationDialog("Reset the smart card?", isPresented: $confirmingReset, titleVisibility: .visible) {
      Button("Reset Card", role: .destructive) { model.resetSmartCard() }
    } message: {
      Text("The keys are destroyed and the PIN returns to 123456. Any pairing stops working; unpair first to keep your account tidy.")
    }
  }

  /// Password needs a saved password first, so picking it asks for one.
  private func unlockMode(_ card: DaemonModel.SmartCard) -> Binding<UnlockMode> {
    Binding(get: { card.unlockMode }, set: { mode in
      if mode == .password && card.passwordStored != true { editingPassword = true } else { model.setUnlockMode(mode) }
    })
  }

  @ViewBuilder private func passwordRow(stored: Bool) -> some View {
    HStack {
      RowLabel(title: "Password", detail: stored ? "Saved in your login keychain." : "Not saved yet.", symbol: "key.fill", tint: .orange)
      Spacer()
      if stored {
        Button("Forget") { model.forgetPassword() }
      }
      Button(stored ? "Change…" : "Save…") { editingPassword = false }
    }
    .disabled(model.smartCardAction != nil)
    if let error = model.smartCardError {
      Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
    }
  }

  @ViewBuilder private func pinSections(_ card: DaemonModel.SmartCard) -> some View {
    Section {
      Toggle(isOn: enabled(card)) {
        RowLabel(title: "Smart Card", detail: card.encrypted ? "The sensor's flash is encrypted." : "Stays off on a sensor whose flash is not encrypted.",
                 symbol: "creditcard.fill", tint: .green)
      }
      .disabled(!card.encrypted && !card.enabled || model.smartCardAction != nil)
    }
    Section {
      SmartCardSteps(model: model, card: card)
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
  }

  private func enabled(_ card: DaemonModel.SmartCard) -> Binding<Bool> {
    Binding(get: { card.enabled }, set: { model.setSmartCard(enabled: $0) })
  }
}

/// The card's three steps, ticked off from its own state: keys, a PIN of
/// your own, pairing with this account. Shown in Settings and in the setup
/// window.
struct SmartCardSteps: View {
  @ObservedObject var model: DaemonModel
  var card: DaemonModel.SmartCard
  @State private var confirmingPair = false

  var body: some View {
    Group {
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
      step(3, "Pair with Your Account", done: card.paired == true, detail: pairingText) {
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
    }
    .confirmationDialog("Pair the smart card with your account?", isPresented: $confirmingPair, titleVisibility: .visible) {
      Button("Pair") { model.pairSmartCard() }
    } message: {
      Text("The lock screen will accept the card's PIN and a touch. Keep your password and a second admin account, and never turn on smart card enforcement.")
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

  private var pairingText: String {
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
    case "save": return "Checking your password; the first time, touch the sensor…"
    case "password": return "Switching to your password…"
    case "pin": return "Switching to PIN and touch…"
    default: return "Unpairing…"
    }
  }
}

/// Asks for the Mac password password mode types. mactouchd checks it
/// against the account before keeping it; the first time it also takes the
/// sensor's key, which needs a touch.
struct PasswordSheet: View {
  @ObservedObject var model: DaemonModel
  var thenUse: Bool
  @Environment(\.dismiss) private var dismiss
  @State private var password = ""
  @State private var submitted = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(thenUse ? "Unlock with Your Password" : "Change the Saved Password").font(.headline)
      Text("MacTouch keeps your password in your login keychain. When a password field asks for it, the ring breathes white; touch the sensor and it types the password. Anyone whose finger is enrolled can then unlock this Mac.")
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      SecureField("Mac password", text: $password)
        .onSubmit(save)
      if model.smartCardAction != nil {
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text("Checking it; the first time, touch the sensor when the ring breathes white…").foregroundStyle(.secondary)
        }
      } else if submitted, let error = model.smartCardError {
        Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
      }
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button(thenUse ? "Save and Use" : "Save", action: save)
          .keyboardShortcut(.defaultAction)
          .disabled(password.isEmpty || model.smartCardAction != nil)
      }
    }
    .padding(20)
    .frame(width: 420)
    .onChange(of: model.smartCardAction) {
      if submitted && model.smartCardAction == nil && model.smartCardError == nil { dismiss() }
    }
  }

  private func save() {
    guard !password.isEmpty, model.smartCardAction == nil else { return }
    submitted = true
    model.savePassword(password, thenUse: thenUse)
    password = ""
  }
}
