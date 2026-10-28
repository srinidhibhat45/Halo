import SwiftUI

// Shapes and geometry effects for the ring renderer. Angles are y-down radians, as in
// `RingGeometry`: 0 points right and angles grow clockwise on screen. In y-down space
// `Path.addArc(clockwise: false)` sweeps toward growing angles.

/// A Glass ring segment: an annular sector centred in its rect, separated from its neighbours by
/// parallel-edged gaps of `gap` points, with all four corners rounded by `cornerRadius`.
///
/// Built analytically (outer arc, corner fillets, straight gap edges, inner arc), so it needs no
/// path boolean operations. Every input may change from frame to frame (the Glass theme grows
/// segments out of the hub): the corners shrink continuously when the sector gets too small for
/// them, so the outline never steps, and a sector without area draws nothing.
nonisolated struct AnnularSector: Shape {
    /// Start and end of the sector before the gap is taken off (y-down radians).
    var startAngle: Double
    var endAngle: Double
    var innerRadius: CGFloat
    var outerRadius: CGFloat
    /// Width of the gap between neighbouring sectors, measured perpendicular to their edges.
    var gap: CGFloat
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let span = endAngle - startAngle
        let halfGap = Double(max(gap, 0)) / 2
        let rO = Double(outerRadius), rI = Double(max(innerRadius, 0))
        // The inner edge keeps at least this much arc between its two fillets.
        let margin = 0.01
        guard rO - rI > 0.05, span > margin else { return Path() }
        // Largest corner radius whose fillets still fit the band's thickness and the inner edge:
        // 2·asin((halfGap + k) / (rI + k)) ≤ span − margin  ⇔  k ≤ (σ·rI − halfGap) / (1 − σ).
        let sigma = sin((span - margin) / 2)
        var k = min(Double(cornerRadius), (rO - rI) / 2 - 0.02)
        if sigma < 0.999 { k = min(k, (sigma * rI - halfGap) / (1 - sigma)) }
        k = max(k, 0)
        let rhoO = rO - k, rhoI = rI + k
        guard rhoI > 0, rhoO > rhoI, halfGap + k < rhoI else { return Path() }
        let insetO = asin((halfGap + k) / rhoO)
        let insetI = asin((halfGap + k) / rhoI)
        guard span - 2 * insetI > 0 else { return Path() }

        let aO0 = startAngle + insetO, aO1 = endAngle - insetO
        let aI0 = startAngle + insetI, aI1 = endAngle - insetI
        func polar(_ r: Double, _ a: Double) -> CGPoint {
            CGPoint(x: center.x + CGFloat(cos(a) * r), y: center.y + CGFloat(sin(a) * r))
        }
        let radius = CGFloat(k)
        var p = Path()
        p.addArc(center: center, radius: outerRadius, startAngle: .radians(aO0), endAngle: .radians(aO1), clockwise: false)
        p.addArc(center: polar(rhoO, aO1), radius: radius, startAngle: .radians(aO1), endAngle: .radians(endAngle + .pi / 2), clockwise: false)
        p.addArc(center: polar(rhoI, aI1), radius: radius, startAngle: .radians(endAngle + .pi / 2), endAngle: .radians(aI1 + .pi), clockwise: false)
        p.addArc(center: center, radius: CGFloat(rI), startAngle: .radians(aI1), endAngle: .radians(aI0), clockwise: true)
        p.addArc(center: polar(rhoI, aI0), radius: radius, startAngle: .radians(aI0 + .pi), endAngle: .radians(startAngle + 1.5 * .pi), clockwise: false)
        p.addArc(center: polar(rhoO, aO0), radius: radius, startAngle: .radians(startAngle + 1.5 * .pi), endAngle: .radians(aO0 + 2 * .pi), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// A Glass sector's geometry at one moment of an animation (y-down radians, points from the
/// ring centre).
nonisolated struct SectorGeometry: Equatable {
    var midAngle: Double
    /// Angular width before the gap is taken off.
    var span: Double
    var innerRadius: CGFloat
    var outerRadius: CGFloat
    var gap: CGFloat
    var cornerRadius: CGFloat

    var midRadius: CGFloat { (innerRadius + outerRadius) / 2 }

    var shape: AnnularSector {
        AnnularSector(startAngle: midAngle - span / 2, endAngle: midAngle + span / 2, innerRadius: innerRadius,
                      outerRadius: outerRadius, gap: gap, cornerRadius: cornerRadius)
    }

    /// Offset from the ring centre of the point `radius` out along the sector's middle.
    func point(atRadius radius: CGFloat) -> CGPoint {
        CGPoint(x: CGFloat(cos(midAngle)) * radius, y: CGFloat(sin(midAngle)) * radius)
    }

    /// This sector extruding out of a point: `progress` 0 is nothing at `radius` in direction
    /// `angle`, 1 is the sector itself. The outer edge leads and the inner edge trails, so the
    /// glass reads as flowing outward; the sector swings from `angle` to its own direction and
    /// widens from a narrow petal on the way. Past 1 (a settling spring) it travels on slightly
    /// but never widens, so neighbours never overlap.
    func emerging(fromAngle angle: Double, radius: CGFloat, progress: Double) -> SectorGeometry {
        let t = max(progress, 0), widening = min(t, 1)
        var g = self
        g.midAngle = Progress.lerp(angle, midAngle, t)
        g.outerRadius = Progress.lerp(radius, outerRadius, t)
        g.innerRadius = Progress.lerp(radius, innerRadius, pow(t, 1.5))
        g.span = span * Progress.lerp(0.45, 1, widening)
        g.gap = gap * CGFloat(widening)
        return g
    }

    /// The sector grown by `amount` of its thickness, mostly outward (the highlight's lift).
    func lifted(by amount: CGFloat) -> SectorGeometry {
        let band = outerRadius - innerRadius
        var g = self
        g.innerRadius -= band * amount * 0.4
        g.outerRadius += band * amount * 1.2
        return g
    }
}

/// A disc of `radius` centred in its rect: the Glass hub, which grows from a point.
nonisolated struct HubDisc: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        guard radius > 0.05 else { return Path() }
        return Path(ellipseIn: CGRect(x: rect.midX - radius, y: rect.midY - radius, width: radius * 2, height: radius * 2))
    }
}

/// A Classic bubble, optionally with Logitech's folder "tab": a small circle fused to the
/// bubble's outer edge by smooth fillets (a metaball-like bump).
///
/// `tabProgress` 1 shows the tab, 0 retracts it inside the bubble (an open folder); animatable.
nonisolated struct BubbleShape: Shape {
    /// Direction the tab points (y-down radians), normally away from the ring centre.
    var tabAngle: Double
    var tabProgress: CGFloat

    /// Tab radius, distance of its centre from the bubble centre, and the fillet radius, as
    /// fractions of the bubble radius (a 16 pt tab on a 46 pt bubble, sticking out 8 pt).
    static let tabRadius: CGFloat = 0.34
    static let tabDistance: CGFloat = 1.0
    static let filletRadius: CGFloat = 0.16

    var animatableData: CGFloat {
        get { tabProgress }
        set { tabProgress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let bigR = min(rect.width, rect.height) / 2
        let circle = Path(ellipseIn: CGRect(x: rect.midX - bigR, y: rect.midY - bigR, width: bigR * 2, height: bigR * 2))
        let r2 = bigR * Self.tabRadius * max(0, min(tabProgress, 1))
        let d = bigR * Self.tabDistance
        let f = bigR * Self.filletRadius
        guard r2 > 0, d + r2 > bigR + 0.25 else { return circle }

        // Work in the tab's frame (x along the tab direction); the fillet circles touch both the
        // bubble and the tab from outside, above and below the axis.
        let x = (d * d + (bigR + f) * (bigR + f) - (r2 + f) * (r2 + f)) / (2 * d)
        let y2 = (bigR + f) * (bigR + f) - x * x
        guard y2 > 0 else { return circle }
        let y = y2.squareRoot()
        let phi = atan2(Double(y), Double(x))           // where the fillets meet the bubble
        let beta1 = atan2(Double(y), Double(-x))        // fillet: towards the bubble centre
        let beta2 = atan2(Double(y), Double(d - x))     // fillet: towards the tab centre
        let gamma = atan2(Double(y), Double(x - d))     // where the fillets meet the tab

        var p = Path()
        p.addArc(center: .zero, radius: bigR, startAngle: .radians(phi), endAngle: .radians(2 * .pi - phi), clockwise: false)
        p.addArc(center: CGPoint(x: x, y: -y), radius: f, startAngle: .radians(beta1), endAngle: .radians(beta2), clockwise: true)
        p.addArc(center: CGPoint(x: d, y: 0), radius: r2, startAngle: .radians(-gamma), endAngle: .radians(gamma), clockwise: false)
        p.addArc(center: CGPoint(x: x, y: y), radius: f, startAngle: .radians(-beta2), endAngle: .radians(-beta1), clockwise: true)
        p.closeSubpath()
        let transform = CGAffineTransform(translationX: rect.midX, y: rect.midY).rotated(by: CGFloat(tabAngle))
        return p.applying(transform)
    }

    /// Centre of the tab relative to the bubble centre, for placing the tab's glyph.
    static func tabCenter(bubbleRadius: CGFloat, angle: Double) -> CGPoint {
        let d = bubbleRadius * tabDistance
        return CGPoint(x: CGFloat(cos(angle)) * d, y: CGFloat(sin(angle)) * d)
    }

    /// How far the tab sticks out beyond the bubble's edge.
    static func tabProtrusion(bubbleRadius: CGFloat) -> CGFloat {
        bubbleRadius * (tabDistance + tabRadius - 1)
    }
}

/// The thin ")"-shaped arc Logitech draws inside a folder's tab, bulging away from the ring.
nonisolated struct TabArcGlyph: Shape {
    var angle: Double
    var bubbleRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = BubbleShape.tabCenter(bubbleRadius: bubbleRadius, angle: angle)
        let inset = bubbleRadius * 0.1
        let center = CGPoint(x: rect.midX + c.x - CGFloat(cos(angle)) * inset,
                             y: rect.midY + c.y - CGFloat(sin(angle)) * inset)
        let half = 0.62   // ±36°
        var p = Path()
        p.addArc(center: center, radius: bubbleRadius * 0.17, startAngle: .radians(angle - half), endAngle: .radians(angle + half), clockwise: false)
        return p
    }
}

/// An arc around the centre of its rect (for stroking): `radius` out, `halfSpan` either side of
/// `angle`. Glass marks folder segments with one along their outer edge.
nonisolated struct RingArc: Shape {
    var angle: Double
    var halfSpan: Double
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: radius,
                 startAngle: .radians(angle - halfSpan), endAngle: .radians(angle + halfSpan), clockwise: false)
        return p
    }
}

/// Logitech's hover tooltip: a capsule filling its rect, with a small rounded notch on the side
/// nearest `target` (a point in the rect's coordinate space, usually the bubble's centre).
nonisolated struct TooltipShape: Shape {
    var target: CGPoint
    var notchWidth: CGFloat
    var notchDepth: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = rect.height / 2
        let capsule = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        // Nearest point on the capsule's spine, then out along the direction to the target.
        let spine = CGPoint(x: min(max(target.x, rect.minX + radius), rect.maxX - radius), y: rect.midY)
        let dx = target.x - spine.x, dy = target.y - spine.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > radius + 1, notchDepth > 0 else { return capsule }
        let u = CGPoint(x: dx / length, y: dy / length)
        let n = CGPoint(x: -u.y, y: u.x)
        func point(_ along: CGFloat, _ across: CGFloat) -> CGPoint {
            CGPoint(x: spine.x + u.x * along + n.x * across, y: spine.y + u.y * along + n.y * across)
        }
        let baseDistance = radius - 2
        let tipDistance = radius + notchDepth
        let half = notchWidth / 2
        var notch = Path()
        notch.move(to: point(baseDistance, half))
        notch.addLine(to: point(tipDistance - notchDepth * 0.28, half * 0.24))
        notch.addQuadCurve(to: point(tipDistance - notchDepth * 0.28, -half * 0.24), control: point(tipDistance, 0))
        notch.addLine(to: point(baseDistance, -half))
        notch.closeSubpath()
        return capsule.union(notch)
    }
}

/// A decaying horizontal shake: three oscillations each time `progress` advances by one.
nonisolated struct ShakeEffect: GeometryEffect {
    var progress: CGFloat
    var amplitude: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let phase = progress - progress.rounded(.down)
        let x = amplitude * (1 - phase) * CGFloat(sin(Double(phase) * 2 * .pi * 3))
        return ProjectionTransform(CGAffineTransform(translationX: x, y: 0))
    }
}

/// Where a single-line label sits: pushed outward from a bubble until its nearest edge is
/// `clearance` points from the bubble centre, inside the canvas.
///
/// Labels go radially outward (Logitech's placement). One that doesn't fit the canvas there is
/// tried above and below its bubble too, and the candidate that covers the fewest bubbles wins.
struct RadialLabelPlacement: Equatable {
    /// Label centre relative to the ring centre.
    var center: CGPoint
    var size: CGSize
    /// The bubble centre in the label's own coordinate space (for the tooltip notch).
    var target: CGPoint

    /// - Parameters:
    ///   - anchor: the bubble centre relative to the ring centre.
    ///   - halfCanvas: half the canvas side; the label stays `margin` inside it.
    ///   - obstacles: centres of the other bubbles (radius `obstacleRadius`) to avoid covering;
    ///     `dimmedObstacles` (the inactive root ring behind a fan) matter half as much.
    init(anchor: CGPoint, clearance: CGFloat, size: CGSize, halfCanvas: CGFloat, margin: CGFloat,
         obstacles: [CGPoint] = [], dimmedObstacles: [CGPoint] = [], obstacleRadius: CGFloat = 0) {
        let length = (anchor.x * anchor.x + anchor.y * anchor.y).squareRoot()
        let radial = length > 0.5 ? CGPoint(x: anchor.x / length, y: anchor.y / length) : CGPoint(x: 0, y: -1)
        let limit = CGSize(width: max(0, halfCanvas - margin - size.width / 2), height: max(0, halfCanvas - margin - size.height / 2))
        func clamped(_ p: CGPoint) -> CGPoint {
            CGPoint(x: min(max(p.x, -limit.width), limit.width), y: min(max(p.y, -limit.height), limit.height))
        }
        /// How deeply a label centred at `c` covers bubbles; its own bubble counts most.
        func penalty(_ c: CGPoint) -> CGFloat {
            let spine = max(0, size.width / 2 - size.height / 2)
            func depth(_ o: CGPoint, _ r: CGFloat) -> CGFloat {
                let dx = max(abs(o.x - c.x) - spine, 0), dy = abs(o.y - c.y)
                return max(0, r - ((dx * dx + dy * dy).squareRoot() - size.height / 2))
            }
            return 4 * depth(anchor, clearance - 1)
                + obstacles.reduce(0) { $0 + depth($1, obstacleRadius) }
                + dimmedObstacles.reduce(0) { $0 + depth($1, obstacleRadius) / 2 }
        }

        var c = clamped(Self.center(anchor: anchor, direction: radial, clearance: clearance, size: size))
        var best = penalty(c)
        if best > 0 {
            let down = CGPoint(x: 0, y: radial.y >= 0 ? 1 : -1)
            for direction in [down, CGPoint(x: 0, y: -down.y)] {
                let candidate = clamped(Self.center(anchor: anchor, direction: direction, clearance: clearance, size: size))
                let score = penalty(candidate) + 2   // a slight preference for the radial spot
                if score < best {
                    best = score
                    c = candidate
                }
            }
        }
        center = c
        self.size = size
        target = CGPoint(x: anchor.x - (c.x - size.width / 2), y: anchor.y - (c.y - size.height / 2))
    }

    /// Centre of a capsule of `size` moved from `anchor` along unit `direction` until the
    /// capsule is `clearance` from the anchor. The capsule is a horizontal spine of half-length
    /// `a` thickened by h/2, so this solves for the spine's distance.
    private static func center(anchor: CGPoint, direction u: CGPoint, clearance: CGFloat, size: CGSize) -> CGPoint {
        let a = max(0, size.width / 2 - size.height / 2)
        let reach = clearance + size.height / 2
        let ux = abs(u.x), uy = abs(u.y)
        var t = uy > 0.001 ? reach / uy : .greatestFiniteMagnitude
        if ux * t > a {
            t = a * ux + max(reach * reach - a * a * uy * uy, 0).squareRoot()
        }
        return CGPoint(x: anchor.x + u.x * t, y: anchor.y + u.y * t)
    }
}
