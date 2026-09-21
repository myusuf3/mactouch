import AppKit
import Combine
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
  private let content: NSHostingView<RequestView>
  private var subscription: AnyCancellable?

  init(model: DaemonModel) {
    self.model = model
    panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.isMovableByWindowBackground = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.becomesKeyOnlyIfNeeded = true
    content = NSHostingView(rootView: RequestView(model: model))
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
    panel.orderFrontRegardless()
  }

  private func hide() {
    panel.orderOut(nil)
  }
}

struct RequestView: View {
  @ObservedObject var model: DaemonModel

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: "touchid")
        .font(.system(size: 36))
        .foregroundStyle(model.request?.kind == "nonce" ? Color.primary : Color.blue)
      VStack(alignment: .leading, spacing: 3) {
        Text(model.request?.kind == "nonce" ? "Authentication request" : "Fingerprint requested")
          .font(.headline)
        Text(model.request?.reason ?? "")
          .foregroundStyle(.secondary)
          .lineLimit(2)
        Text(instruction)
          .font(.caption)
          .foregroundStyle(model.noMatches > 0 ? Color.red : Color.secondary)
      }
      Spacer(minLength: 12)
      Button("Cancel") { model.cancel() }
    }
    .padding(20)
    .frame(width: 440)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private var instruction: String {
    switch model.noMatches {
    case 0: return "Touch the sensor"
    case 1: return "No match, try again"
    default: return "No match \(model.noMatches) times, try again"
    }
  }
}
