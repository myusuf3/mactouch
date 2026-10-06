import AppKit
import Combine
import MacTouchKit
import MacTouchModel
import SwiftUI

/// The window a fingerprint request puts on screen, modelled on the system
/// Touch ID prompt: a borderless floating panel in the centre of the screen
/// with the pointer. It never becomes key, so a password being typed into
/// the terminal that asked keeps going there. Shown on `pending`, gone on
/// `done`, however the request ended.
final class RequestPanel {
  private let model: DaemonModel
  private let panel: NSPanel
  private let content: NSHostingView<RequestContent>
  private var subscription: AnyCancellable?

  init(model: DaemonModel) {
    self.model = model
    panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.isMovableByWindowBackground = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.becomesKeyOnlyIfNeeded = true
    content = NSHostingView(rootView: RequestContent(model: model))
    panel.contentView = content
    subscription = model.$request
      .map { $0 != nil }
      .removeDuplicates()
      .sink { [weak self] pending in pending ? self?.show() : self?.hide() }
  }

  private func show() {
    panel.setContentSize(content.fittingSize)
    let pointer = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
    if let area = screen?.visibleFrame {
      let size = panel.frame.size
      panel.setFrameOrigin(NSPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2))
    }
    panel.alphaValue = 0
    panel.orderFrontRegardless()
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.18
      panel.animator().alphaValue = 1
    }
  }

  private func hide() {
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.2
      panel.animator().alphaValue = 0
    } completionHandler: { [panel] in
      if panel.alphaValue == 0 { panel.orderOut(nil) }
    }
  }
}

struct RequestContent: View {
  @ObservedObject var model: DaemonModel

  var body: some View {
    RequestView(kind: model.request?.kind ?? "plain", reason: model.request?.reason ?? "", noMatches: model.noMatches) {
      model.cancel()
    }
  }
}

/// The card itself: the sensor breathing in the colour the real ring shows
/// for this kind of request, so the eye can go from screen to desk and back.
struct RequestView: View {
  var kind: String
  var reason: String
  var noMatches: Int
  var cancel: () -> Void

  var body: some View {
    VStack(spacing: 14) {
      DeviceView(ring: RingState(.breathe, kind == "plain" ? .blue : .white), size: 88)
        .modifier(Shake(travel: CGFloat(noMatches)))
        .animation(.linear(duration: 0.45), value: noMatches)
        .padding(.top, 4)
      VStack(spacing: 4) {
        Text(title)
          .font(.headline)
        Text(reason)
          .font(.callout)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .lineLimit(3)
          .fixedSize(horizontal: false, vertical: true)
      }
      Text(instruction)
        .font(.callout.weight(.medium))
        .foregroundStyle(noMatches > 0 ? Color.red : Color.secondary)
        .contentTransition(.opacity)
        .animation(.smooth, value: noMatches)
      // The card cannot be interrupted once it waits; the host gives up
      // on its own when the wait ends. Cancelling a password request leaves
      // that field to be typed by hand.
      if kind == "plain" || kind == "nonce" || kind == "password" {
        Button(action: cancel) {
          Text("Cancel").frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .padding(.top, 2)
      }
    }
    .padding(22)
    .frame(width: 300)
    .panelBackground()
    .padding(24)
  }

  private var title: String {
    switch kind {
    case "nonce": return "Authentication Request"
    case "piv": return "Smart Card Sign-In"
    case "password": return "Password Requested"
    case "firmware": return "Firmware Update"
    default: return "Fingerprint Requested"
    }
  }

  private var instruction: String {
    switch noMatches {
    case 0: return "Touch the sensor"
    case 1: return "No match. Try again"
    default: return "No match \(noMatches) times. Try again"
    }
  }
}

/// A horizontal shake, one full shake per unit of travel.
private struct Shake: GeometryEffect {
  var travel: CGFloat
  var animatableData: CGFloat {
    get { travel }
    set { travel = newValue }
  }

  func effectValue(size: CGSize) -> ProjectionTransform {
    ProjectionTransform(CGAffineTransform(translationX: 9 * sin(travel * .pi * 6), y: 0))
  }
}

private extension View {
  /// Liquid Glass where the system has it, the regular material before.
  /// The panel is borderless and clear, so the card draws its own shadow
  /// and the outer padding leaves room for it.
  @ViewBuilder func panelBackground() -> some View {
    let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
    if #available(macOS 26.0, *) {
      glassEffect(.regular, in: shape)
    } else {
      background(.regularMaterial, in: shape)
        .overlay(shape.strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
    }
  }
}
