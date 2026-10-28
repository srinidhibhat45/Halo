import Foundation
import Testing
@testable import HaloCore

@Suite("RingGeometry")
struct RingGeometryTests {
    let eight = RingGeometry(slotCount: 8)

    @Test("Slot 0 is at the top and slots run clockwise")
    func clockwiseFromTop() {
        #expect(eight.slot(dx: 0, dy: -100, deadZone: 20) == 0)
        #expect(eight.slot(dx: 70, dy: -70, deadZone: 20) == 1)
        #expect(eight.slot(dx: 100, dy: 0, deadZone: 20) == 2)
        #expect(eight.slot(dx: 70, dy: 70, deadZone: 20) == 3)
        #expect(eight.slot(dx: 0, dy: 100, deadZone: 20) == 4)
        #expect(eight.slot(dx: -70, dy: 70, deadZone: 20) == 5)
        #expect(eight.slot(dx: -100, dy: 0, deadZone: 20) == 6)
        #expect(eight.slot(dx: -70, dy: -70, deadZone: 20) == 7)
    }

    @Test("Sector boundaries split evenly around each slot centre")
    func boundaries() {
        // Slot 0 spans -112.5° ... -67.5°.
        let justInside = (-90.0 + 22.4) * .pi / 180
        let justOutside = (-90.0 + 22.6) * .pi / 180
        #expect(eight.slot(atAngle: justInside) == 0)
        #expect(eight.slot(atAngle: justOutside) == 1)
        #expect(eight.slot(atAngle: (-90.0 - 22.4) * .pi / 180) == 0)
        #expect(eight.slot(atAngle: (-90.0 - 22.6) * .pi / 180) == 7)
    }

    @Test("Dead zone and max radius return nil")
    func deadZoneAndMaxRadius() {
        #expect(eight.slot(dx: 5, dy: -5, deadZone: 20) == nil)
        #expect(eight.slot(dx: 0, dy: -500, deadZone: 20, maxRadius: 300) == nil)
        #expect(eight.slot(dx: 0, dy: -500, deadZone: 20, maxRadius: nil) == 0)
    }

    @Test("Works for every supported slot count", arguments: Array(4...12))
    func everyCount(n: Int) {
        let g = RingGeometry(slotCount: n)
        for i in 0..<n {
            let p = g.offset(of: i, radius: 100)
            #expect(g.slot(dx: p.x, dy: p.y, deadZone: 10) == i)
        }
    }

    @Test("Arrow keys jump, then walk toward the arrow")
    func arrows() {
        #expect(eight.slot(from: nil, toward: .right) == 2)
        #expect(eight.slot(from: nil, toward: .left) == 6)
        #expect(eight.slot(from: 0, toward: .right) == 1)
        #expect(eight.slot(from: 1, toward: .right) == 2)
        #expect(eight.slot(from: 2, toward: .right) == 2)
        #expect(eight.slot(from: 0, toward: .down) == 1)   // opposite: tie breaks clockwise
    }

    @Test("Hysteresis holds the current slot just past its edge")
    func hysteresis() {
        let five = 5.0 * .pi / 180
        // 24° clockwise from north: past slot 0's edge (22.5°) but inside the 5° hysteresis.
        let a = (-90.0 + 24) * .pi / 180
        let (dx, dy) = (cos(a) * 100, sin(a) * 100)
        #expect(eight.slot(dx: dx, dy: dy, deadZone: 16) == 1)
        #expect(eight.slot(dx: dx, dy: dy, deadZone: 16, current: 0, hysteresis: five) == 0)
        // 30°: beyond the hysteresis band.
        let b = (-90.0 + 30) * .pi / 180
        #expect(eight.slot(dx: cos(b) * 100, dy: sin(b) * 100, deadZone: 16, current: 0, hysteresis: five) == 1)
        // Dead zone still wins.
        #expect(eight.slot(dx: 1, dy: 1, deadZone: 16, current: 0, hysteresis: five) == nil)
    }

    @Test("Tab cycles both ways")
    func cycling() {
        #expect(eight.slot(after: nil) == 0)
        #expect(eight.slot(after: 7) == 0)
        #expect(eight.slot(after: 0, clockwise: false) == 7)
        #expect(eight.slot(after: nil, clockwise: false) == 7)
    }
}

@Suite("ArcGeometry")
struct ArcGeometryTests {
    @Test("Children fan out centred on the folder's direction")
    func centred() {
        let right = ArcGeometry(count: 3, centerAngle: 0)
        #expect(abs(right.angle(of: 1)) < 1e-9)
        #expect(abs(right.angle(of: 0) + .pi / 8) < 1e-9)
        #expect(right.slot(dx: 100, dy: 0, minRadius: 50) == 1)
        #expect(right.slot(dx: 100, dy: -40, minRadius: 50) == 0)   // up-right
        #expect(right.slot(dx: 100, dy: 40, minRadius: 50) == 2)
    }

    @Test("Outside the arc, inside the min radius, or beyond max picks nothing")
    func outside() {
        let up = ArcGeometry(count: 3, centerAngle: -.pi / 2)
        #expect(up.slot(dx: 0, dy: 100, minRadius: 50) == nil)      // opposite side
        #expect(up.slot(dx: 0, dy: -30, minRadius: 50) == nil)
        #expect(up.slot(dx: 0, dy: -400, minRadius: 50, maxRadius: 300) == nil)
        #expect(up.slot(dx: 0, dy: -100, minRadius: 50) == 1)
    }

    @Test("Arcs that cross the ±π seam still resolve")
    func seam() {
        let left = ArcGeometry(count: 4, centerAngle: .pi)
        for i in 0..<4 {
            let p = left.offset(of: i, radius: 100)
            #expect(left.slot(dx: p.x, dy: p.y, minRadius: 10) == i)
        }
    }

    @Test("Many children never wrap past a full circle")
    func clampStep() {
        let many = ArcGeometry(count: 20, centerAngle: 0)
        #expect(many.step <= 2 * .pi / 20 + 1e-12)
    }
}
