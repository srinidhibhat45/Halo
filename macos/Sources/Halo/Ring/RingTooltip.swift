import AppKit
import HaloCore
import SwiftUI

/// A Classic label: Logitech's hover tooltip (a near-white capsule with a notch pointing at the
/// bubble, `labelMode == .hub`) or a smaller caption chip without a notch (`.always`).
///
/// Sized from the measured title and placed radially outward from its bubble, so the notch can
/// point at the bubble from any direction.
struct ClassicLabel: View {
    enum Style: Equatable {
        case tooltip
        case chip
    }

    let title: String
    let style: Style
    let placement: RadialLabelPlacement
    /// Ring size multiplier (Medium = 1).
    let scale: CGFloat
    let environment: RingEnvironment

    var body: some View {
        let shape = TooltipShape(
            target: placement.target,
            notchWidth: style == .tooltip ? 9 * scale : 0,
            notchDepth: style == .tooltip ? 4 * scale : 0
        )
        Text(title)
            .font(.system(size: Self.fontSize(style, scale: scale), weight: .medium))
            .foregroundStyle(ClassicPalette.glyph)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: placement.size.width, height: placement.size.height)
            .background {
                ZStack {
                    shape
                        .fill(ClassicPalette.tooltip.opacity(environment.reduceTransparency ? 1 : 0.96))
                        .shadow(color: .black.opacity(environment.colorScheme == .dark ? 0.32 : 0.14), radius: 4 * scale, y: 1.5 * scale)
                    shape.stroke(.black.opacity(environment.increaseContrast ? 0.4 : 0.07), lineWidth: environment.increaseContrast ? 1 : 0.5)
                }
            }
            .offset(x: placement.center.x, y: placement.center.y)
            .accessibilityHidden(true)
    }

    static func fontSize(_ style: Style, scale: CGFloat) -> CGFloat {
        style == .tooltip ? 11 * scale : 10 * scale
    }

    /// The label's size for `title`: the measured text plus 8 pt padding each side, at most
    /// `maxWidth` (longer titles truncate).
    static func size(of title: String, style: Style, scale: CGFloat) -> CGSize {
        let height = (style == .tooltip ? 20 : 17) * scale
        let padding = (style == .tooltip ? 8 : 7) * scale
        let text = LabelMetrics.width(of: title, size: fontSize(style, scale: scale), weight: .medium)
        let width = min(text + 2 * padding + 2, 190 * scale)
        return CGSize(width: max(width, height), height: height)
    }
}

extension RingViewModel {
    /// Where the Classic label of slot `index` of the shown level goes: radially outward of its
    /// bubble, clear of its tab or dot, avoiding the other bubbles (and, behind a fanned-out
    /// folder, the dimmed root ring). Shared by the SwiftUI and Core Animation renderers.
    func classicLabelPlacement(of index: Int, style: ClassicLabel.Style) -> RadialLabelPlacement {
        let m = metrics
        let scale = m.unit
        let face = SlotFace(ring.slots[index])
        let anchor = slotOffset(index)
        let r = m.slotSize / 2
        var extra: CGFloat = 0
        switch face.kind {
        case .folder: extra = BubbleShape.tabProtrusion(bubbleRadius: r)
        case .adjustable: extra = 3 * scale
        case .empty, .action: break
        }
        if mode == .editor { extra = max(extra, 4 * scale) }
        let clearance = r + extra + (style == .tooltip ? 6 : 4) * scale
        var dimmed: [CGPoint] = []
        if isFanned, let root = rootRing {
            let geometry = RingGeometry(slotCount: root.slotCount)
            dimmed = (0..<root.slotCount).map { geometry.offset(of: $0, radius: Double(m.slotCenterRadius)) }
        }
        return RadialLabelPlacement(
            anchor: anchor,
            clearance: clearance,
            size: ClassicLabel.size(of: face.title, style: style, scale: scale),
            halfCanvas: m.canvasSide / 2,
            margin: 4 * scale,
            obstacles: (0..<ring.slotCount).map(slotOffset).filter { $0 != anchor },
            dimmedObstacles: dimmed,
            obstacleRadius: m.slotSize / 2 + 2 * scale
        )
    }
}

/// A Classic tooltip arriving with its highlight: it slides `distance` points outward from its
/// bubble while fading in (only fades without movement).
struct TooltipSlide: Transition {
    var placement: RadialLabelPlacement
    var distance: CGFloat
    var moves: Bool

    func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(at(phase.isIdentity ? 1 : 0))
    }

    /// The tooltip at `progress` of its arrival.
    func at(_ progress: Double) -> TooltipReveal {
        // From the bubble centre (`target`, in the label's space) to the label's centre.
        let dx = placement.size.width / 2 - placement.target.x, dy = placement.size.height / 2 - placement.target.y
        let length = max((dx * dx + dy * dy).squareRoot(), 0.001)
        let travel = moves ? distance : 0
        return TooltipReveal(progress: progress, offset: CGSize(width: dx / length * travel, height: dy / length * travel))
    }
}

/// A tooltip `progress` of the way in: transparent and `offset` short of its place at 0.
struct TooltipReveal: ViewModifier {
    var progress: Double
    var offset: CGSize

    func body(content: Content) -> some View {
        let remaining = CGFloat(1 - progress)
        content
            .opacity(progress)
            .offset(x: -offset.width * remaining, y: -offset.height * remaining)
    }
}

/// Classic colours (Logitech's light bubbles with the legibility fixes from SPEC §6).
enum ClassicPalette {
    /// Idle bubble fill, rgb(243,241,241); drawn at 90 % (solid with Reduce Transparency).
    static let bubble = Color(.sRGB, red: 243 / 255, green: 241 / 255, blue: 241 / 255)
    /// Glyphs and tooltip text, #1D1D1F.
    static let glyph = Color(.sRGB, red: 0x1D / 255, green: 0x1D / 255, blue: 0x1F / 255)
    /// Default highlight tile, #111.
    static let tile = Color(.sRGB, red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255)
    /// Hub disc, rgb(130,130,135); drawn at 55 %.
    static let hub = Color(.sRGB, red: 130 / 255, green: 130 / 255, blue: 135 / 255)
    /// Tooltip capsule, rgb(250,250,250).
    static let tooltip = Color(.sRGB, red: 250 / 255, green: 250 / 255, blue: 250 / 255)
    /// Dashed outline of empty slots: mid grey that reads on light and dark backgrounds.
    static let emptyStroke = Color(.sRGB, red: 142 / 255, green: 142 / 255, blue: 147 / 255)
    /// Slot-number badges.
    static let badge = Color(.sRGB, red: 108 / 255, green: 108 / 255, blue: 113 / 255)
}
