import HaloCore
import SwiftUI

/// A large icon with its name underneath (apps), for the Add to Ring picker and the Add App Ring
/// sheet. Clicking it chooses it.
struct IconTile<Icon: View>: View {
    let title: String
    var help: String?
    /// Drawn with the keyboard highlight (what Return chooses).
    var isHighlighted = false
    /// A small badge on the icon's corner, e.g. "this app already has a ring".
    var badge: String?
    /// A short accent-coloured line under a one-line title, e.g. "10 actions".
    var caption: String?
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    @ViewState private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                icon()
                    .frame(width: 44, height: 44)
                    .overlay(alignment: .bottomTrailing) {
                        if badge != nil {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 15))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.accentColor)
                                .background(Circle().fill(.background).padding(1))
                                .offset(x: 3, y: 3)
                                .accessibilityHidden(true)
                        }
                    }
                if let caption {
                    // Title and caption share the title's two lines, so rows stay aligned.
                    VStack(spacing: 1) {
                        Text(title)
                            .font(.caption)
                            .lineLimit(1)
                        Text(caption)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.tint)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text(title)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .lineLimit(2, reservesSpace: true)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 5)
            .padding(.horizontal, 2)
            .background(TileBackground(isHighlighted: isHighlighted, isHovered: isHovered, resting: false))
            .contentShape(RoundedRectangle(cornerRadius: TileBackground.radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovered = $0 }
        .help(help ?? title)
        .accessibilityLabel([title, badge, caption].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }
}

/// An action as a tile: icon, title and a one-line description. Clicking it chooses it.
struct ActionTile: View {
    let title: String
    let subtitle: String
    let icon: IconSpec
    var isHighlighted = false
    let action: () -> Void

    @ViewState private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                SlotIconTile(icon: icon, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(TileBackground(isHighlighted: isHighlighted, isHovered: isHovered, resting: true))
            .contentShape(RoundedRectangle(cornerRadius: TileBackground.radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovered = $0 }
        .help(subtitle)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }
}

/// The shape behind a tile: the keyboard highlight (accent), a hover wash, or a faint resting
/// fill that makes action tiles read as buttons.
struct TileBackground: View {
    static let radius: CGFloat = 10

    var isHighlighted: Bool
    var isHovered: Bool
    var resting: Bool

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        shape
            .fill(fill)
            .overlay {
                if isHighlighted {
                    shape.strokeBorder(Color.accentColor, lineWidth: contrast == .increased ? 2 : 1.5)
                } else if contrast == .increased, resting {
                    shape.strokeBorder(.separator)
                }
            }
    }

    private var fill: Color {
        if isHighlighted { return Color.accentColor.opacity(0.16) }
        if isHovered { return Color.primary.opacity(0.08) }
        return resting ? Color.primary.opacity(0.04) : .clear
    }
}

/// Items in rows of equal-width columns (the last row padded), so tiles line up.
struct TileRows<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    let columns: Int
    var spacing: CGFloat = 6
    @ViewBuilder let cell: (Item) -> Cell

    var body: some View {
        let width = max(columns, 1)
        let rows = stride(from: 0, to: items.count, by: width).map { Array(items[$0..<min($0 + width, items.count)]) }
        VStack(spacing: spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(row) { item in
                        cell(item)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(row.count..<width, id: \.self) { _ in
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: 1)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }
}
