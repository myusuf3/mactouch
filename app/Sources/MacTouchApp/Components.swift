import SwiftUI

/// A symbol on a coloured squircle, the way System Settings marks its panes.
struct SettingsIcon: View {
  var symbol: String
  var tint: Color
  var size: CGFloat = 20

  var body: some View {
    RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
      .fill(tint.gradient)
      .overlay(
        Image(systemName: symbol)
          .font(.system(size: size * 0.55, weight: .semibold))
          .foregroundStyle(.white)
          .shadow(color: .black.opacity(0.15), radius: 0.5, y: 0.5)
      )
      .overlay(
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
          .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
      )
      .frame(width: size, height: size)
  }
}

/// A row's leading icon, title and a line of detail under it.
struct RowLabel: View {
  var title: String
  var detail: String?
  var symbol: String
  var tint: Color

  var body: some View {
    HStack(spacing: 10) {
      SettingsIcon(symbol: symbol, tint: tint, size: 26)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
        if let detail {
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }
}

/// A short status in a tinted capsule: "Up to date", "Paired".
struct StatusBadge: View {
  var text: String
  var tint: Color

  var body: some View {
    Text(text)
      .font(.caption.weight(.medium))
      .foregroundStyle(tint)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(tint.opacity(0.14), in: Capsule())
  }
}

/// A section footer as System Settings sets them: small, secondary and
/// aligned with the rows above.
struct Footnote: View {
  var text: String

  init(_ text: String) { self.text = text }

  var body: some View {
    Text(text)
      .font(.footnote)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.leading)
      .frame(maxWidth: .infinity, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 10)
  }
}

/// A version in a monospaced capsule; "0.2.2 → 0.2.3" for an update.
struct VersionCapsule: View {
  var text: String

  var body: some View {
    Text(text)
      .font(.system(.body, design: .monospaced).weight(.medium))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 14)
      .padding(.vertical, 6)
      .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
  }
}
