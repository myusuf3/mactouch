import AppKit
import MacTouchKit
import SwiftUI

extension LEDColour {
  /// The ring's LEDs as they look lit, a little richer than the system
  /// colours so a swatch reads as light rather than paint.
  var light: Color {
    switch self {
    case .off: return Color(white: 0.32)
    case .blue: return Color(red: 0.24, green: 0.50, blue: 1.00)
    case .green: return Color(red: 0.20, green: 0.88, blue: 0.42)
    case .cyan: return Color(red: 0.16, green: 0.84, blue: 1.00)
    case .red: return Color(red: 1.00, green: 0.23, blue: 0.25)
    case .magenta: return Color(red: 1.00, green: 0.24, blue: 0.84)
    case .yellow: return Color(red: 1.00, green: 0.82, blue: 0.18)
    case .white: return Color(red: 0.93, green: 0.95, blue: 1.00)
    }
  }

  var name: String { rawValue.capitalized }

  /// A round swatch for menus, which draw SwiftUI images as templates;
  /// an AppKit image that is not a template keeps its colour.
  var swatch: NSImage {
    let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
      let dot = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
      if self == .off {
        NSColor.secondaryLabelColor.setStroke()
        dot.lineWidth = 1
        dot.stroke()
      } else {
        NSColor(self.light).setFill()
        dot.fill()
      }
      return true
    }
    image.isTemplate = false
    return image
  }
}

extension LEDMode {
  var adjective: String {
    switch self {
    case .off: return "Off"
    case .on: return "Steady"
    case .breathe: return "Breathing"
    case .flash: return "Flashing"
    case .fadein: return "Fading in"
    case .fadeout: return "Fading out"
    }
  }
}

extension RingState {
  /// "Breathing red", "Steady blue and white", "Off".
  var phrase: String {
    guard mode != .off else { return "Off" }
    let colours = colour2 == colour ? colour.rawValue : "\(colour.rawValue) and \(colour2.rawValue)"
    return "\(mode.adjective) \(colours)"
  }
}

/// The sensor on the desk: a dark glass disc with its ridges, set in a
/// graphite bezel, and the RGB ring around it lit the way the real one is.
/// Breathing and flashing follow the firmware's rhythm closely enough to
/// recognise at a glance; with Reduce Motion the ring holds steady.
struct DeviceView: View {
  var ring: RingState?
  var size: CGFloat = 120

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    TimelineView(.animation(paused: !animates)) { context in
      let lit = light(at: context.date)
      ZStack {
        bezel
        glow(lit)
        sensor
      }
      .frame(width: size, height: size)
    }
    .accessibilityElement()
    .accessibilityLabel("Ring: \(ring?.phrase.lowercased() ?? "unknown")")
  }

  private var animates: Bool {
    guard !reduceMotion, let mode = ring?.mode else { return false }
    return mode == .breathe || mode == .flash
  }

  /// The colour showing and how brightly, 0 to 1.
  private func light(at date: Date) -> (colour: LEDColour, level: Double) {
    guard let ring, ring.mode != .off else { return (.off, 0) }
    let t = date.timeIntervalSinceReferenceDate
    switch ring.mode {
    case .breathe where !reduceMotion:
      let phase = (1 - cos(t * 2 * .pi / 2.6)) / 2
      return (ring.colour, 0.12 + 0.88 * phase)
    case .flash where !reduceMotion:
      let beat = Int(t / 0.45)
      guard beat.isMultiple(of: 2) else { return (ring.colour2 == ring.colour ? .off : ring.colour2, ring.colour2 == ring.colour ? 0 : 1) }
      return (ring.colour, 1)
    default:
      return (ring.colour, 1)
    }
  }

  private var bezel: some View {
    Circle()
      .fill(LinearGradient(colors: [Color(white: 0.30), Color(white: 0.09)], startPoint: .top, endPoint: .bottom))
      .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom), lineWidth: max(0.5, size * 0.008)))
      .shadow(color: .black.opacity(0.35), radius: size * 0.08, y: size * 0.04)
  }

  private func glow(_ lit: (colour: LEDColour, level: Double)) -> some View {
    let colour = lit.colour.light
    let width = size * 0.055
    return ZStack {
      Circle()
        .strokeBorder(Color.black.opacity(0.55), lineWidth: width * 1.6)
        .padding(size * 0.105)
      Circle()
        .strokeBorder(colour.opacity(lit.level), lineWidth: width)
        .padding(size * 0.12)
        .blur(radius: size * 0.05)
        .opacity(lit.level)
      Circle()
        .strokeBorder(colour.opacity(0.25 + 0.75 * lit.level), lineWidth: width)
        .padding(size * 0.12)
        .overlay(
          Circle()
            .strokeBorder(.white.opacity(0.55 * lit.level), lineWidth: width * 0.3)
            .padding(size * 0.12 + width * 0.35)
            .blur(radius: width * 0.2)
        )
        .opacity(lit.colour == .off ? 0.35 : 1)
    }
  }

  private var sensor: some View {
    Circle()
      .fill(RadialGradient(colors: [Color(white: 0.17), Color(white: 0.05)], center: .init(x: 0.4, y: 0.3), startRadius: 0, endRadius: size * 0.36))
      .overlay(
        Image(systemName: "touchid")
          .font(.system(size: size * 0.34, weight: .light))
          .foregroundStyle(LinearGradient(colors: [Color(white: 0.42), Color(white: 0.2)], startPoint: .top, endPoint: .bottom))
      )
      .overlay(
        Circle()
          .fill(LinearGradient(colors: [.white.opacity(0.16), .clear], startPoint: .top, endPoint: .center))
          .padding(size * 0.02)
      )
      .padding(size * 0.2)
  }
}
