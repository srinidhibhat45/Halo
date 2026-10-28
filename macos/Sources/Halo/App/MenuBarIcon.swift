import AppKit
import SwiftUI

/// Halo's menu bar glyph: eight ring segments around a dot (the ring around the pointer), drawn
/// in code as a template image so it follows the menu bar's appearance.
enum MenuBarIcon {
    /// Side of the glyph's square canvas, in points.
    nonisolated static let side: CGFloat = 18

    private static let active = makeImage(paused: false)
    private static let paused = makeImage(paused: true)

    /// The glyph; the paused variant is dimmed and struck through.
    static func image(paused isPaused: Bool) -> NSImage { isPaused ? paused : active }

    /// Builds the image lazily from a drawing handler, so it is crisp at any backing scale.
    /// `nonisolated` because AppKit may call the handler wherever the image is drawn.
    private nonisolated static func makeImage(paused: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            draw(paused: paused)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = paused ? "Halo (paused)" : "Halo"
        return image
    }

    /// Draws the glyph into the current context (y up). Only alpha matters in a template image.
    private nonisolated static func draw(paused: Bool) {
        let center = NSPoint(x: side / 2, y: side / 2)
        NSColor.black.withAlphaComponent(paused ? 0.4 : 1).set()

        let radius: CGFloat = 6
        let segments = 8
        let step = 360 / CGFloat(segments)
        let gap = 1.4 / radius * 180 / .pi   // a constant 1.4 pt gap between segments, in degrees
        for i in 0..<segments {
            let mid = 90 - CGFloat(i) * step   // segment 0 at 12 o'clock, then clockwise
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius, startAngle: mid - (step - gap) / 2, endAngle: mid + (step - gap) / 2)
            arc.lineWidth = 2
            arc.stroke()
        }
        let hub: CGFloat = 1.7
        NSBezierPath(ovalIn: NSRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2)).fill()

        guard paused else { return }
        let slash = NSBezierPath()
        slash.move(to: NSPoint(x: 3, y: side - 3))
        slash.line(to: NSPoint(x: side - 3, y: 3))
        slash.lineCapStyle = .round
        // Cut a channel through the ring so the slash stays legible, then draw it at full strength.
        NSGraphicsContext.current?.compositingOperation = .clear
        slash.lineWidth = 3.6
        slash.stroke()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        NSColor.black.set()
        slash.lineWidth = 1.6
        slash.stroke()
    }
}

/// The menu bar extra's label: Halo's glyph, dimmed and struck through while paused.
struct MenuBarLabel: View {
    var body: some View {
        let isPaused = AppModel.shared.isPaused
        Image(nsImage: MenuBarIcon.image(paused: isPaused))
            .accessibilityLabel(isPaused ? "Halo, paused" : "Halo")
    }
}
