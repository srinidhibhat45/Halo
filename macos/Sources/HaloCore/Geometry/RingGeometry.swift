import CoreGraphics
import Foundation

/// Angle maths for a ring of `slotCount` equal sectors.
///
/// Coordinates are y-down (SwiftUI's convention): angle 0 points right, π/2 points down, and
/// increasing angles run clockwise on screen. Slot 0 is centred on `startAngle` (top by default).
public struct RingGeometry: Hashable, Sendable {
    public var slotCount: Int
    public var startAngle: Double

    public init(slotCount: Int, startAngle: Double = -.pi / 2) {
        precondition(slotCount > 0, "A ring needs at least one slot")
        self.slotCount = slotCount
        self.startAngle = startAngle
    }

    /// Angular width of one sector, in radians.
    public var step: Double { 2 * .pi / Double(slotCount) }

    /// Centre angle of slot `i`, in radians (not normalised).
    public func centerAngle(of i: Int) -> Double { startAngle + Double(i) * step }

    /// Start and end angles of slot `i`'s sector, optionally shrunk by `gap` radians on each side.
    public func sector(of i: Int, gap: Double = 0) -> (start: Double, end: Double) {
        let c = centerAngle(of: i)
        return (c - step / 2 + gap, c + step / 2 - gap)
    }

    /// Offset from the ring centre to the middle of slot `i` at `radius` (y-down).
    public func offset(of i: Int, radius: Double) -> CGPoint {
        let a = centerAngle(of: i)
        return CGPoint(x: cos(a) * radius, y: sin(a) * radius)
    }

    /// The slot whose sector contains angle `a` (radians, y-down).
    public func slot(atAngle a: Double) -> Int {
        let relative = Self.normalize(a - startAngle + step / 2)
        return min(Int(relative / step), slotCount - 1)
    }

    /// The slot pointed at by an offset from the centre (y-down), or nil inside the dead zone or
    /// beyond `maxRadius` (pass nil for an unbounded, marking-menu-style target).
    public func slot(dx: Double, dy: Double, deadZone: Double, maxRadius: Double? = nil) -> Int? {
        let r = (dx * dx + dy * dy).squareRoot()
        guard r >= deadZone else { return nil }
        if let maxRadius, r > maxRadius { return nil }
        return slot(atAngle: atan2(dy, dx))
    }

    /// Like `slot(dx:dy:deadZone:maxRadius:)`, but keeps `current` highlighted until the pointer
    /// is more than `hysteresis` radians past its sector edge, so the highlight doesn't flicker
    /// on a boundary.
    public func slot(dx: Double, dy: Double, deadZone: Double, maxRadius: Double? = nil, current: Int?, hysteresis: Double) -> Int? {
        guard let candidate = slot(dx: dx, dy: dy, deadZone: deadZone, maxRadius: maxRadius) else { return nil }
        guard let current, current != candidate, (0..<slotCount).contains(current) else { return candidate }
        let distance = Self.angularDistance(atan2(dy, dx), centerAngle(of: current))
        return distance <= step / 2 + hysteresis ? current : candidate
    }

    /// The slot closest to a compass direction, for arrow-key navigation.
    public func slot(toward direction: Direction) -> Int { slot(atAngle: direction.angle) }

    /// Next slot clockwise (or counter-clockwise) from `index`; from nil, starts at slot 0
    /// (or the last slot going backwards).
    public func slot(after index: Int?, clockwise: Bool = true) -> Int {
        guard let index else { return clockwise ? 0 : slotCount - 1 }
        return ((index + (clockwise ? 1 : -1)) % slotCount + slotCount) % slotCount
    }

    /// Arrow-key navigation. With nothing highlighted, jumps to the slot nearest the arrow's
    /// direction. Otherwise steps one slot (clockwise or counter-clockwise, whichever turns toward
    /// the arrow), so repeated presses walk around the ring and stop once facing that direction.
    public func slot(from current: Int?, toward direction: Direction) -> Int {
        guard let current else { return slot(toward: direction) }
        let target = direction.angle
        func distance(_ i: Int) -> Double { Self.angularDistance(centerAngle(of: i), target) }
        let clockwise = slot(after: current, clockwise: true)
        let counter = slot(after: current, clockwise: false)
        return [current, clockwise, counter].min { distance($0) < distance($1) - 1e-9 } ?? current
    }

    /// Normalises an angle into 0 ..< 2π.
    public static func normalize(_ a: Double) -> Double {
        let twoPi = 2 * Double.pi
        let r = a.truncatingRemainder(dividingBy: twoPi)
        return r < 0 ? r + twoPi : r
    }

    /// Smallest absolute difference between two angles, in 0 ... π.
    public static func angularDistance(_ a: Double, _ b: Double) -> Double {
        let d = normalize(a - b)
        return min(d, 2 * .pi - d)
    }

    public enum Direction: Sendable {
        case up, down, left, right, upLeft, upRight, downLeft, downRight

        /// y-down angle.
        public var angle: Double {
            switch self {
            case .right: 0
            case .downRight: .pi / 4
            case .down: .pi / 2
            case .downLeft: 3 * .pi / 4
            case .left: .pi
            case .upLeft: -3 * .pi / 4
            case .up: -.pi / 2
            case .upRight: -.pi / 4
            }
        }
    }
}

/// Layout of a folder's children fanned out on an outer arc, centred on the folder's direction
/// (Logitech-style): child `i` sits at `centerAngle + (i - (count - 1) / 2) * step`.
///
/// Angles are y-down radians like `RingGeometry`. Children are picked by direction only, and
/// only within half a step beyond either end of the arc.
public struct ArcGeometry: Hashable, Sendable {
    public var count: Int
    public var centerAngle: Double
    public var step: Double

    /// 22.5°: nine children span 180°.
    public static let defaultStep = Double.pi / 8

    public init(count: Int, centerAngle: Double, step: Double = ArcGeometry.defaultStep) {
        precondition(count > 0, "An arc needs at least one child")
        self.count = count
        self.centerAngle = centerAngle
        // Never wrap past a full circle.
        self.step = min(step, 2 * .pi / Double(count))
    }

    /// Centre angle of child `i`.
    public func angle(of i: Int) -> Double {
        centerAngle + (Double(i) - Double(count - 1) / 2) * step
    }

    /// Offset from the ring centre to child `i` at `radius` (y-down).
    public func offset(of i: Int, radius: Double) -> CGPoint {
        let a = angle(of: i)
        return CGPoint(x: cos(a) * radius, y: sin(a) * radius)
    }

    /// The child whose direction contains angle `a`, or nil outside the arc.
    public func slot(atAngle a: Double) -> Int? {
        // Signed angle from the first child, in -π ..< π around the arc's centre.
        var rel = RingGeometry.normalize(a - centerAngle + .pi) - .pi
        rel += Double(count - 1) / 2 * step
        let index = Int((rel / step).rounded())
        guard (0..<count).contains(index), abs(rel - Double(index) * step) <= step / 2 + 1e-9 else { return nil }
        return index
    }

    /// The child pointed at by an offset (y-down), or nil closer than `minRadius`, beyond
    /// `maxRadius` (nil = unbounded) or outside the arc.
    public func slot(dx: Double, dy: Double, minRadius: Double, maxRadius: Double? = nil) -> Int? {
        let r = (dx * dx + dy * dy).squareRoot()
        guard r >= minRadius else { return nil }
        if let maxRadius, r > maxRadius { return nil }
        return slot(atAngle: atan2(dy, dx))
    }
}
