import MacTouchKit
import MacTouchModel
import SwiftUI

/// The resting colour, picked from tiles lit the way the sensor would be,
/// and the stack of layers that take the ring over.
struct RingPane: View {
  @ObservedObject var model: DaemonModel

  var body: some View {
    Form {
      Section {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
          ForEach(LEDColour.allCases, id: \.self) { colour in
            ColourTile(colour: colour, selected: model.idle == colour) { model.setIdle(colour) }
          }
        }
        .padding(.vertical, 4)
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
    if model.deviceConnected, model.layers.contains(layer.name) {
      if model.layers.last == layer.name {
        StatusBadge(text: "Showing", tint: model.idle?.accent ?? .accentColor)
      } else {
        StatusBadge(text: "Covered", tint: .secondary)
      }
    }
  }
}

/// One colour as a tile holding a small sensor lit in it. The chosen tile
/// is outlined in the window's tint, which is the ring colour itself.
struct ColourTile: View {
  var colour: LEDColour
  var selected: Bool
  var action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      VStack(spacing: 7) {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(colour == .off ? AnyShapeStyle(.quaternary.opacity(0.5)) : AnyShapeStyle(colour.light.opacity(hovering ? 0.22 : 0.14)))
          .overlay(DeviceView(ring: .steady(colour), size: 42))
          .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .strokeBorder(.separator, lineWidth: 0.5)
          )
          .frame(height: 64)
          .padding(3)
          .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
              .strokeBorder(.tint, lineWidth: 2.5)
              .opacity(selected ? 1 : 0)
          )
        Text(colour.name)
          .font(.callout.weight(selected ? .semibold : .regular))
          .foregroundStyle(selected ? .primary : .secondary)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .animation(.smooth(duration: 0.2), value: hovering)
    .animation(.spring(duration: 0.3), value: selected)
    .accessibilityLabel(colour.name)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}
