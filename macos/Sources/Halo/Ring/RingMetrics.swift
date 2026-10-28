import CoreGraphics
import HaloCore

/// Sizes of the ring for a theme, scale and slot count, in points.
///
/// Shared by the renderer (drawing), the overlay (panel size, placement, hit-testing) and the
/// editor (hit-testing clicks and drops), so all three always agree. The renderer may tune the
/// numbers; the overlay and editor rely only on the hit-testing and placement fields.
///
/// - Classic (Logitech-exact, measured from Logi Options+ screenshots): flat round bubbles on a
///   circle around a small hub showing ×. Medium: 46 pt bubbles at radius 82.5 pt, 31 pt hub,
///   20 pt glyphs, 37 pt app icons. Folder children fan out on an outer circle at 2 × radius,
///   22.5° apart, centred on the folder's direction.
/// - Glass: one segmented annulus of Liquid Glass sectors around a glass hub that shows the
///   highlighted slot's name. Medium: outer radius 140 pt, inner/outer 0.42, 4 pt gaps. Folder
///   children fan out on an outer band.
struct RingMetrics: Equatable {
    var theme: RingTheme
    /// The user's size multiplier (Medium = 1), for drawing details not listed here.
    var scale: CGFloat

    // MARK: Hit-testing and placement (used by overlay and editor)

    /// Radius of the centre hub (a click inside it means "back"/"close").
    var hubRadius: CGFloat
    /// While the trigger is held, pointer offsets shorter than this highlight nothing.
    var holdDeadZone: CGFloat
    /// In tap mode, the pointer must leave the hub to highlight (so hover and click agree).
    var tapDeadZone: CGFloat { hubRadius }
    /// In tap mode, pointer/clicks farther than this highlight nothing / dismiss.
    var maxHitRadius: CGFloat
    /// Angular hysteresis (radians) that keeps the highlight from flickering on a boundary.
    var hysteresis: Double { 5 * .pi / 180 }
    /// Distance from the centre to the fanned-out folder children's centres.
    var folderRadius: CGFloat
    /// Angle between neighbouring folder children (radians).
    var childStep: Double { ArcGeometry.defaultStep }
    /// Radius around the ring centre that must stay on screen when placing the ring (the ring
    /// plus room for a tooltip); the transparent canvas beyond it may extend off screen.
    var clampRadius: CGFloat

    // MARK: Drawing

    /// Distance from the centre to each slot's centre (bubble centre / icon centre).
    var slotCenterRadius: CGFloat
    /// Classic: bubble diameter. Glass: the band's thickness.
    var slotSize: CGFloat
    /// Outer edge of the drawn ring (bubbles' outer edge / annulus outer radius).
    var outerRadius: CGFloat
    /// Inner edge of the drawn ring (bubbles' inner edge / annulus inner radius).
    var innerRadius: CGFloat
    /// Glass: gap between segments along the mid-line. Classic: minimum gap between bubbles.
    var segmentGap: CGFloat
    /// SF Symbol glyph size.
    var iconSize: CGFloat
    /// App icons are drawn larger than glyphs (they carry their own padding).
    var appIconSize: CGFloat
    var hubIconSize: CGFloat
    var labelFontSize: CGFloat
    var hubLabelFontSize: CGFloat
    /// Height of the hover tooltip capsule (Classic).
    var tooltipHeight: CGFloat
    /// Scale applied to the highlighted slot (Classic: none, like Logitech).
    var highlightScale: CGFloat
    /// Room around the fanned-out folder ring for tooltips, shadow and glow.
    var canvasPadding: CGFloat

    /// Width and height of the square the ring is drawn in (and the overlay panel's size). Big
    /// enough for fanned-out folder children and their tooltips.
    var canvasSide: CGFloat { (folderRadius + slotSize / 2 + canvasPadding) * 2 }

    /// Glass segment gap as an angle at the mid-line (radians, per side).
    var halfGapAngle: Double {
        let mid = Double((outerRadius + innerRadius) / 2)
        return mid > 0 ? Double(segmentGap) / mid / 2 : 0
    }

    init(theme: RingTheme, scale: Double, slotCount: Int) {
        let s = CGFloat(max(0.5, scale))
        let n = CGFloat(max(1, slotCount))
        self.theme = theme
        self.scale = s
        switch theme {
        case .classic:
            let bubble: CGFloat = 46 * s
            let minGap: CGFloat = 17 * s
            // Logitech's ring has 8 bubbles; with more, grow the radius so bubbles don't touch.
            let radius = max(82.5 * s, n * (bubble + minGap) / (2 * .pi))
            slotSize = bubble
            slotCenterRadius = radius
            outerRadius = radius + bubble / 2
            innerRadius = radius - bubble / 2
            segmentGap = minGap
            hubRadius = 15.5 * s
            iconSize = 20 * s
            appIconSize = 37 * s
            hubIconSize = 12 * s
            highlightScale = 1
            folderRadius = radius * 2
            tooltipHeight = 20 * s
            // Room for ~140 pt tooltips placed radially outward of fanned-out children.
            canvasPadding = 150 * s
            labelFontSize = 11 * s
            hubLabelFontSize = 11 * s
        case .glass:
            let outer = max(140 * s, n * 26 * s / (2 * .pi) + 90 * s)
            let inner = outer * 0.42
            outerRadius = outer
            innerRadius = inner
            slotSize = outer - inner
            slotCenterRadius = (outer + inner) / 2
            segmentGap = 4 * s
            hubRadius = inner - 8 * s
            iconSize = 24 * s
            appIconSize = 34 * s
            hubIconSize = 22 * s
            highlightScale = 1.05
            folderRadius = outer + 12 * s + slotSize / 2
            tooltipHeight = 0
            canvasPadding = 40 * s
            labelFontSize = 10 * s
            hubLabelFontSize = 12.5 * s
        }
        holdDeadZone = 16 * s
        maxHitRadius = outerRadius + 60 * s
        clampRadius = outerRadius * highlightScale + (theme == .classic ? 40 : 16) * s
    }
}
