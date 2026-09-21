import MacTouchKit
import MacTouchModel
import SwiftUI

/// The Settings window: one pane per concern, in the toolbar style the HIG
/// asks for. A menu bar app has no main window, so opening this one also
/// activates the app or the window would land behind whatever is in front.
struct SettingsView: View {
  @ObservedObject var model: DaemonModel
  @ObservedObject var loginItem: LoginItem

  var body: some View {
    TabView {
      GeneralPane(model: model, loginItem: loginItem)
        .tabItem { Label("General", systemImage: "gearshape") }
      FingersPane(model: model)
        .tabItem { Label("Fingers", systemImage: "touchid") }
      DiagnosticsPane(model: model)
        .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
    }
    .frame(width: 480)
    .onAppear { NSApp.activate(ignoringOtherApps: true) }
  }
}

struct GeneralPane: View {
  @ObservedObject var model: DaemonModel
  @ObservedObject var loginItem: LoginItem
  @AppStorage(showInMenuBarKey) private var showInMenuBar = true

  var body: some View {
    Form {
      Section {
        Picker("Idle colour", selection: idleColour) {
          ForEach(LEDColour.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
        }
        .disabled(!model.deviceConnected)
      } footer: {
        Text("The ring's resting colour, kept on the device.")
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
      }
      Section {
        Toggle("Show in menu bar", isOn: $showInMenuBar)
      } footer: {
        Text("MacTouch keeps running without the icon and still shows fingerprint requests. To bring the icon back, open MacTouch again.")
      }
    }
    .formStyle(.grouped)
    .onAppear { loginItem.refresh() }
  }

  private var idleColour: Binding<LEDColour> {
    Binding(get: { model.idle ?? .off }, set: { model.setIdle($0) })
  }

  private var launchAtLogin: Binding<Bool> {
    Binding(get: { loginItem.isEnabled }, set: { loginItem.set(enabled: $0) })
  }
}

struct FingersPane: View {
  @ObservedObject var model: DaemonModel
  @State private var slotToDelete: Int?

  var body: some View {
    Form {
      Section {
        if model.slots.isEmpty {
          Text("No fingers enrolled")
            .foregroundStyle(.secondary)
        }
        ForEach(model.slots, id: \.self) { slot in
          HStack {
            TextField("Slot \(slot)", text: name(slot), prompt: Text("Unnamed"))
            Button("Delete…", role: .destructive) { slotToDelete = slot }
          }
        }
      }
      Section {
        HStack {
          Button("Enrol Finger") { model.enrol() }
            .disabled(!canEnrol)
          Text(enrolmentText)
            .foregroundStyle(.secondary)
        }
      }
    }
    .formStyle(.grouped)
    .onAppear { model.refreshSlots() }
    .confirmationDialog("Delete this finger?", isPresented: deleting, titleVisibility: .visible, presenting: slotToDelete) { slot in
      Button("Delete \(title(slot))", role: .destructive) { model.delete(slot: slot) }
    } message: { slot in
      Text("Slot \(slot) will be erased from the device. sudo and su will fall back to your password until another finger is enrolled.")
    }
  }

  private var canEnrol: Bool {
    guard model.deviceConnected, model.firstFreeSlot != nil else { return false }
    if case .running = model.enrolment { return false }
    return true
  }

  private var enrolmentText: String {
    switch model.enrolment {
    case .idle:
      guard model.deviceConnected else { return "Connect the device to enrol" }
      return model.firstFreeSlot.map { "Next free slot: \($0)" } ?? "All \(model.capacity) slots are used"
    case .running(let step):
      switch step {
      case "touch": return "Touch the sensor"
      case "lift": return "Lift your finger"
      case "touch_again": return "Touch the sensor again"
      case "processing": return "Processing…"
      default: return "Waiting for the sensor…"
      }
    case .done(let slot): return "Enrolled \(title(slot))"
    case .failed(let reason): return "Enrolment failed: \(reason)"
    }
  }

  private func title(_ slot: Int) -> String {
    model.names[slot].map { "\"\($0)\"" } ?? "slot \(slot)"
  }

  private func name(_ slot: Int) -> Binding<String> {
    Binding(get: { model.names[slot] ?? "" }, set: { model.rename(slot, to: $0) })
  }

  private var deleting: Binding<Bool> {
    Binding(get: { slotToDelete != nil }, set: { if !$0 { slotToDelete = nil } })
  }
}

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
              Label(check.name.capitalized, systemImage: symbol(check.verdict))
                .foregroundStyle(colour(check.verdict))
            }
          }
        } else {
          Text("Checking…")
            .foregroundStyle(.secondary)
        }
      }
      Section {
        Button("Check Again") { model.refreshHealth() }
      }
    }
    .formStyle(.grouped)
    .onAppear { model.refreshHealth() }
    .onChange(of: model.deviceConnected) { model.refreshHealth() }
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
