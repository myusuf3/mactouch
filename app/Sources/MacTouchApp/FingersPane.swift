import MacTouchModel
import SwiftUI

struct FingersPane: View {
  @ObservedObject var model: DaemonModel
  @State private var slotToDelete: Int?
  @State private var enrolling = false

  var body: some View {
    Form {
      PaneHeader(.fingers, summary: "A touch approves sudo, scripts and agents. Names stay on this Mac; the sensor only knows slot numbers.")
      Section {
        if model.slots.isEmpty {
          Text(model.deviceConnected ? "No fingers yet. Add one to approve with a touch." : "Connect the sensor to see its fingers.")
            .foregroundStyle(.secondary)
        }
        ForEach(model.slots, id: \.self) { slot in
          HStack(spacing: 10) {
            SettingsIcon(symbol: "touchid", tint: .red, size: 26)
            TextField("Name", text: name(slot), prompt: Text("Finger \(slot)"))
              .textFieldStyle(.plain)
              .labelsHidden()
            Text("Slot \(slot)")
              .font(.caption.monospacedDigit())
              .foregroundStyle(.tertiary)
            Button { slotToDelete = slot } label: { Image(systemName: "minus.circle.fill") }
              .buttonStyle(.borderless)
              .foregroundStyle(.secondary)
              .help("Delete this finger")
          }
        }
        Button { enrolling = true } label: {
          HStack(spacing: 10) {
            Image(systemName: "plus")
              .font(.system(size: 13, weight: .semibold))
              .frame(width: 26, height: 26)
              .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 26 * 0.26, style: .continuous))
            Text("Add a Finger…")
          }
          .foregroundStyle(Color.accentColor)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!model.deviceConnected || model.firstFreeSlot == nil)
      } header: {
        Text("Enrolled")
      } footer: {
        if model.deviceConnected { Footnote("\(model.slots.count) of \(model.capacity) slots used") }
      }
    }
    .formStyle(.grouped)
    .onAppear { model.refreshSlots() }
    .sheet(isPresented: $enrolling) { EnrolmentSheet(model: model) }
    .confirmationDialog("Delete \(slotToDelete.map(title) ?? "this finger")?", isPresented: deleting, titleVisibility: .visible, presenting: slotToDelete) { slot in
      Button("Delete", role: .destructive) { model.delete(slot: slot) }
    } message: { _ in
      Text("It is erased from the sensor. With no fingers left, sudo falls back to your password.")
    }
  }

  private func title(_ slot: Int) -> String {
    model.names[slot].map { "\"\($0)\"" } ?? "finger \(slot)"
  }

  private func name(_ slot: Int) -> Binding<String> {
    Binding(get: { model.names[slot] ?? "" }, set: { model.rename(slot, to: $0) })
  }

  private var deleting: Binding<Bool> {
    Binding(get: { slotToDelete != nil }, set: { if !$0 { slotToDelete = nil } })
  }
}

/// Enrolling one finger, drawn like Touch ID setup: the print fills in as
/// the sensor takes each image, and turns green when it is saved.
struct EnrolmentSheet: View {
  @ObservedObject var model: DaemonModel
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var slot: Int?

  var body: some View {
    VStack(spacing: 18) {
      FingerprintProgress(progress: progress, done: isDone, failed: isFailed)
        .padding(.top, 8)
      VStack(spacing: 6) {
        Text(title)
          .font(.title3.weight(.semibold))
        Text(detail)
          .font(.callout)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .frame(minHeight: 36, alignment: .top)
      }
      .animation(.smooth, value: title)
      if isDone {
        TextField("Name", text: $name, prompt: Text("Name this finger, like Right Index"))
          .textFieldStyle(.roundedBorder)
          .frame(width: 260)
      }
      HStack {
        if isFailed {
          Button("Try Again") { start() }
        }
        Spacer()
        if isDone {
          Button("Done") { save() }
            .keyboardShortcut(.defaultAction)
        } else {
          Button("Cancel", role: .cancel) { cancel() }
            .keyboardShortcut(.cancelAction)
        }
      }
    }
    .padding(24)
    .frame(width: 380)
    .onAppear(perform: start)
  }

  private func start() {
    slot = model.firstFreeSlot
    model.enrol()
  }

  private func save() {
    if let slot, !name.isEmpty { model.rename(slot, to: name) }
    dismiss()
  }

  private func cancel() {
    if case .running = model.enrolment { model.cancel() }
    dismiss()
  }

  private var isDone: Bool { if case .done = model.enrolment { return true } else { return false } }
  private var isFailed: Bool { if case .failed = model.enrolment { return true } else { return false } }

  private var step: String? { if case .running(let step) = model.enrolment { return step } else { return nil } }

  private var progress: Double {
    switch model.enrolment {
    case .done: return 1
    case .running: return ["touch": 0.12, "lift": 0.45, "touch_again": 0.55, "processing": 0.88][step ?? ""] ?? 0
    default: return 0
    }
  }

  private var title: String {
    switch model.enrolment {
    case .done: return "Finger Added"
    case .failed: return "That Didn't Take"
    default:
      switch step {
      case "lift": return "Lift Your Finger"
      case "touch_again": return "And Once More"
      case "processing": return "Saving…"
      default: return "Place Your Finger"
      }
    }
  }

  private var detail: String {
    switch model.enrolment {
    case .done: return "It can approve requests now."
    case .failed(let reason): return reason == "cancelled" ? "Enrolment was cancelled." : "The sensor said: \(reason)"
    default:
      switch step {
      case "lift": return "Got it. Take your finger off the sensor."
      case "touch_again": return "Rest the same finger on the sensor, a little off centre."
      case "processing": return "Storing the print on the sensor."
      default: return "Rest the finger you want to use flat on the sensor."
      }
    }
  }
}

/// A large fingerprint whose ridges fill from the bottom as enrolment goes.
struct FingerprintProgress: View {
  var progress: Double
  var done: Bool
  var failed: Bool
  @State private var pulse = false

  var body: some View {
    ZStack {
      Circle()
        .fill(tint.opacity(0.1))
        .frame(width: 128, height: 128)
        .scaleEffect(pulse && !done && !failed ? 1.06 : 1)
      ridges.foregroundStyle(.quaternary)
      ridges
        .foregroundStyle(tint.gradient)
        .mask(alignment: .bottom) {
          Rectangle().frame(height: 120 * progress)
        }
      if done {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 30))
          .symbolRenderingMode(.palette)
          .foregroundStyle(.white, .green)
          .background(Circle().fill(.background).padding(2))
          .offset(x: 44, y: 44)
          .transition(.scale.combined(with: .opacity))
      }
    }
    .frame(width: 140, height: 140)
    .animation(.spring(duration: 0.6, bounce: 0.25), value: progress)
    .animation(.spring(duration: 0.4, bounce: 0.4), value: done)
    .onAppear {
      withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { pulse = true }
    }
  }

  private var ridges: some View {
    Image(systemName: "touchid")
      .font(.system(size: 80, weight: .regular))
      .frame(width: 120, height: 120)
  }

  private var tint: Color { done ? .green : failed ? .orange : .red }
}
