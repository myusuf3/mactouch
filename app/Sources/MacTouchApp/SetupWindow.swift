import AppKit
import Combine
import MacTouchKit
import MacTouchModel
import ServiceManagement
import SwiftUI

/// The setup window, docs/ONBOARDING.md. AppKit owns it rather than a
/// SwiftUI `Window` scene, which macOS 14 would open at every login; this
/// one opens once on its own, the first time the app finds sudo not yet
/// set up, and after that only from the menu.
final class SetupWindow {
  private let model: DaemonModel
  private let defaults: UserDefaults
  private var window: NSWindow?
  private var firstReport: AnyCancellable?
  private static let offeredKey = "setupOffered"

  init(model: DaemonModel, defaults: UserDefaults = .standard) {
    self.model = model
    self.defaults = defaults
    guard !defaults.bool(forKey: Self.offeredKey) else { return }
    // A published value arrives before the property holds it, so the
    // decision waits a turn of the run loop to read the model.
    firstReport = model.$health
      .compactMap { $0 }
      .first()
      .sink { [weak self] _ in DispatchQueue.main.async { self?.offerOnce() } }
    model.refreshHealth()
  }

  /// Opens on the first step not yet done, or the welcome page.
  func show(from start: SetupPage? = nil) {
    let window = self.window ?? makeWindow()
    self.window = window
    let page = start ?? SetupPage.allCases.first { page in
      guard case .step(let step) = page else { return false }
      return !model.isDone(step) && !step.isOptional
    } ?? .done
    window.contentViewController = NSHostingController(rootView: SetupView(model: model, page: page) { [weak window] in
      window?.close()
    })
    window.center()
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  private func offerOnce() {
    defaults.set(true, forKey: Self.offeredKey)
    if model.needsSetup == true { show(from: .welcome) }
  }

  private func makeWindow() -> NSWindow {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
                          styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
    window.title = "Set Up MacTouch"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true
    window.isReleasedWhenClosed = false
    return window
  }
}

enum SetupPage: Hashable, CaseIterable {
  case welcome
  case step(SetupStep)
  case done

  static var allCases: [SetupPage] { [.welcome] + SetupStep.allCases.map(SetupPage.step) + [.done] }

  var next: SetupPage? { Self.allCases.firstIndex(of: self).flatMap { Self.allCases.indices.contains($0 + 1) ? Self.allCases[$0 + 1] : nil } }
  var previous: SetupPage? { Self.allCases.firstIndex(of: self).flatMap { $0 > 0 ? Self.allCases[$0 - 1] : nil } }
}

struct SetupView: View {
  @ObservedObject var model: DaemonModel
  @State var page: SetupPage
  var close: () -> Void
  @State private var enrolling = false

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 14) {
        SetupProgress(model: model, page: page)
          .frame(height: 10)
          .padding(.top, 34)
        DeviceHero(ring: ring, size: isBookend ? 128 : 96)
          .padding(.vertical, isBookend ? 14 : 6)
        VStack(spacing: 6) {
          HStack(spacing: 8) {
            Text(title)
              .font(.title2.weight(.semibold))
            if case .step(let step) = page, step.isOptional {
              StatusBadge(text: "Optional", tint: .secondary)
            }
          }
          Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 380)
        }
        content
          .padding(.top, 6)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 32)
      .frame(maxWidth: .infinity)
      Divider()
      buttons
        .controlSize(.large)
        .padding(16)
    }
    .frame(width: 480, height: 600)
    .tint(model.idle?.accent)
    .animation(.smooth(duration: 0.3), value: page)
    .sheet(isPresented: $enrolling) { EnrolmentSheet(model: model) }
    .onAppear {
      model.refreshSmartCard()
      model.refreshHealth()
    }
  }

  private var isBookend: Bool { page == .welcome || page == .done }

  private var ring: RingState? {
    guard model.daemonRunning else { return nil }
    return model.deviceConnected ? model.ringState : .off
  }

  // MARK: words

  private var title: String {
    switch page {
    case .welcome: return "Welcome to MacTouch"
    case .step(.connect): return "Plug In Your Sensor"
    case .step(.firmware): return "Keep It Current"
    case .step(.finger): return "Add a Finger"
    case .step(.sudo): return "Use Your Finger for sudo"
    case .step(.smartCard): return "Unlock with a Touch"
    case .done: return "You're All Set"
    }
  }

  private var message: String {
    switch page {
    case .welcome: return "A few steps and a touch approves sudo, scripts and agents. It takes a couple of minutes, and you can skip anything."
    case .step(.connect): return "Use a USB-C cable that carries data. MacTouch finds the sensor on its own."
    case .step(.firmware): return "Firmware installs over USB after a touch. If new firmware fails to start, the sensor goes back to the old one."
    case .step(.finger): return "The sensor keeps the print itself; nothing about it is stored on this Mac."
    case .step(.sudo): return "Approve sudo in Terminal with a touch. Your password keeps working whenever you would rather type it."
    case .step(.smartCard): return "At the lock screen, type the card's PIN, then touch the sensor."
    case .done: return "Touch the sensor when your Mac asks. Everything here is in Settings too."
    }
  }

  // MARK: content

  @ViewBuilder private var content: some View {
    switch page {
    case .welcome: EmptyView()
    case .step(.connect): connect
    case .step(.firmware): firmware
    case .step(.finger): finger
    case .step(.sudo): sudo
    case .step(.smartCard): smartCard
    case .done: summary
    }
  }

  @ViewBuilder private var connect: some View {
    if !model.daemonRunning {
      VStack(spacing: 8) {
        Text("MacTouch's background helper is not running.")
          .foregroundStyle(.secondary)
        Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
      }
    } else if model.deviceConnected {
      Done("Connected\(model.firmware.map { " · firmware \($0)" } ?? "")")
    } else {
      HStack(spacing: 8) {
        ProgressView().controlSize(.small)
        Text("Waiting for the sensor…").foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder private var firmware: some View {
    if !model.deviceConnected {
      Waiting("Connect the sensor first.")
    } else if model.firmwareUpdateAvailable || model.firmwareUpdating, let board = model.firmware, let carried = model.bundledFirmware?.version {
      VStack(spacing: 12) {
        VersionCapsule(text: "\(board) → \(carried)")
        if let progress = model.firmwareProgress, model.firmwareUpdating {
          if case .writing(let fraction) = progress {
            ProgressView(value: fraction).frame(width: 260)
          } else {
            ProgressView().progressViewStyle(.linear).frame(width: 260)
          }
          Text(progress == .waitingForTouch ? "Touch the sensor to allow the update" : "Installing; the sensor restarts…")
            .font(.callout).foregroundStyle(.secondary)
        } else {
          Button("Install Update") { model.updateFirmware() }
            .buttonStyle(.borderedProminent)
        }
      }
    } else {
      VStack(spacing: 10) {
        if let board = model.firmware { VersionCapsule(text: board) }
        if case .failed(let reason)? = model.firmwareProgress {
          Label(reason, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        } else {
          Done("Up to date")
        }
      }
    }
  }

  @ViewBuilder private var finger: some View {
    if !model.deviceConnected {
      Waiting("Connect the sensor first.")
    } else if let prints = model.prints, prints > 0 {
      VStack(spacing: 10) {
        Done(prints == 1 ? "1 finger enrolled" : "\(prints) fingers enrolled")
        Button("Add Another…") { enrolling = true }
          .disabled(model.firstFreeSlot == nil)
      }
    } else {
      Button("Add a Finger…") { enrolling = true }
        .buttonStyle(.borderedProminent)
    }
  }

  @ViewBuilder private var sudo: some View {
    if model.isDone(.sudo) {
      Done("sudo accepts your fingerprint")
    } else if !model.canEnableSudo {
      Waiting("This copy of MacTouch cannot turn it on. From the source checkout, run sudo scripts/pam-install.sh.")
    } else if model.sudoSetup == .running {
      VStack(spacing: 8) {
        ProgressView().controlSize(.small)
        Text("Enter your password in the macOS prompt, then touch the sensor when the ring breathes white.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
    } else {
      VStack(spacing: 10) {
        Button("Turn On…") { model.enableSudo() }
          .buttonStyle(.borderedProminent)
          .disabled(!model.daemonRunning)
        if case .failed(let reason)? = model.sudoSetup, reason != "cancelled" {
          Label(reason, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
            .multilineTextAlignment(.center)
        }
      }
    }
  }

  @ViewBuilder private var smartCard: some View {
    if let card = model.smartCard {
      if !card.encrypted {
        Waiting("This sensor's flash is not encrypted, so its smart card stays off.")
      } else if !card.enabled {
        Button("Turn On the Smart Card") { model.setSmartCard(enabled: true) }
          .buttonStyle(.borderedProminent)
      } else {
        Form { Section { SmartCardSteps(model: model, card: card) } }
          .formStyle(.grouped)
          .scrollDisabled(true)
          .scrollContentBackground(.hidden)
          .frame(height: 210)
          .padding(.horizontal, -20)
      }
    } else {
      Waiting(model.deviceConnected ? "Reading the card…" : "Connect the sensor first.")
    }
  }

  private var summary: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(SetupStep.allCases, id: \.self) { step in
        Label {
          Text(summaryTitle(step))
        } icon: {
          Image(systemName: model.isDone(step) ? "checkmark.circle.fill" : "circle.dashed")
            .foregroundStyle(model.isDone(step) ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
        }
        .foregroundStyle(model.isDone(step) ? .primary : .secondary)
      }
    }
  }

  private func summaryTitle(_ step: SetupStep) -> String {
    switch step {
    case .connect: return "Sensor connected"
    case .firmware: return "Firmware up to date"
    case .finger: return "A finger enrolled"
    case .sudo: return "sudo by fingerprint"
    case .smartCard: return "Unlock with the smart card"
    }
  }

  // MARK: buttons

  @ViewBuilder private var buttons: some View {
    HStack(spacing: 12) {
      switch page {
      case .welcome:
        wide("Not Now", action: close)
        wide("Get Started", prominent: true) { advance() }
      case .done:
        wide("Back") { back() }
        wide("Done", prominent: true, action: close)
      case .step(let step):
        wide("Back") { back() }
        if model.isDone(step) {
          wide("Continue", prominent: true) { advance() }
        } else {
          wide("Skip") { advance() }
        }
      }
    }
  }

  private func wide(_ title: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
    Group {
      if prominent {
        Button(action: action) { Text(title).frame(maxWidth: .infinity) }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
      } else {
        Button(action: action) { Text(title).frame(maxWidth: .infinity) }
      }
    }
  }

  private func advance() { if let next = page.next { page = next } }
  private func back() { if let previous = page.previous { page = previous } }
}

/// A step's outcome, with a green tick.
private struct Done: View {
  var text: String
  init(_ text: String) { self.text = text }

  var body: some View {
    Label(text, systemImage: "checkmark.circle.fill")
      .font(.callout.weight(.medium))
      .foregroundStyle(.green)
  }
}

/// Why a step cannot be done yet.
private struct Waiting: View {
  var text: String
  init(_ text: String) { self.text = text }

  var body: some View {
    Text(text)
      .font(.callout)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
  }
}

/// One dot per step: green once done, the tint for the current one.
private struct SetupProgress: View {
  @ObservedObject var model: DaemonModel
  var page: SetupPage

  var body: some View {
    HStack(spacing: 7) {
      ForEach(SetupStep.allCases, id: \.self) { step in
        let current = page == .step(step)
        Capsule()
          .fill(model.isDone(step) ? AnyShapeStyle(Color.green) : current ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
          .frame(width: current ? 20 : 7, height: 7)
      }
    }
    .opacity(page == .welcome ? 0 : 1)
    .animation(.spring(duration: 0.35), value: page)
    .accessibilityHidden(true)
  }
}
