import MacTouchKit
import MacTouchModel
import SwiftUI

/// The resting colour, picked from lit swatches, and the stack of layers
/// that take the ring over, each drawn the way it looks on the device.
struct RingPane: View {
  @ObservedObject var model: DaemonModel

  var body: some View {
    Form {
      PaneHeader(title: "Ring", summary: "The light around the sensor. It rests in your colour and changes when your Mac has something to tell you.") {
        DeviceView(ring: model.deviceConnected ? model.ringState : .off, size: 84)
      }
      Section {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 14) {
          ForEach(LEDColour.allCases, id: \.self) { colour in
            ColourSwatch(colour: colour, selected: model.idle == colour) { model.setIdle(colour) }
          }
        }
        .padding(.vertical, 6)
        .disabled(!model.deviceConnected)
      } header: {
        Text("Resting Colour")
      } footer: {
        Footnote(model.idleCoveredNote ?? "Kept on the sensor, so it shows even before MacTouch starts.")
      }
      Section {
        ForEach(RingLayer.allCases.reversed(), id: \.self) { layer in
          HStack(spacing: 12) {
            DeviceView(ring: sample(layer), size: 30)
            VStack(alignment: .leading, spacing: 2) {
              Text(layer.title)
              Text(layer.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            badge(layer)
          }
        }
        if model.notifyActive {
          Button("Clear Notification Light") { model.clearNotify() }
        }
      } header: {
        Text("What the Ring Shows")
      } footer: {
        Footnote("Higher rows cover lower ones. When one ends, the next shows through.")
      }
    }
    .formStyle(.grouped)
  }

  private func sample(_ layer: RingLayer) -> RingState {
    layer == .idle ? .steady(model.idle ?? .off) : layer.sample
  }

  @ViewBuilder private func badge(_ layer: RingLayer) -> some View {
    let active = model.layers.contains(layer.name)
    if model.deviceConnected, active {
      if model.layers.last == layer.name {
        StatusBadge(text: "Showing", tint: .accentColor)
      } else {
        StatusBadge(text: "Covered", tint: .secondary)
      }
    }
  }
}

/// One colour as a small lit disc. The chosen one carries a ring in the
/// accent colour, like the wallpaper and accent pickers in System Settings.
struct ColourSwatch: View {
  var colour: LEDColour
  var selected: Bool
  var action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      VStack(spacing: 6) {
        ZStack {
          Circle()
            .fill(colour == .off ? AnyShapeStyle(Color(white: 0.12)) : AnyShapeStyle(colour.light.gradient))
            .overlay(Circle().strokeBorder(.white.opacity(colour == .off ? 0.15 : 0.35), lineWidth: 0.5))
            .shadow(color: colour == .off ? .clear : colour.light.opacity(hovering || selected ? 0.8 : 0.45), radius: hovering || selected ? 10 : 6)
            .frame(width: 34, height: 34)
          if colour == .off {
            Image(systemName: "moon.fill")
              .font(.system(size: 12))
              .foregroundStyle(Color(white: 0.5))
          }
          Circle()
            .strokeBorder(Color.accentColor, lineWidth: 2.5)
            .frame(width: 44, height: 44)
            .opacity(selected ? 1 : 0)
        }
        .frame(width: 46, height: 46)
        .scaleEffect(hovering ? 1.06 : 1)
        Text(colour.name)
          .font(.caption)
          .foregroundStyle(selected ? .primary : .secondary)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .animation(.spring(duration: 0.25), value: hovering)
    .animation(.spring(duration: 0.3), value: selected)
    .accessibilityLabel(colour.name)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}
