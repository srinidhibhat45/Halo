import AppKit
import QuartzCore

/// Calls `onTick` once per display frame while running, so the overlay can poll
/// `NSEvent.mouseLocation`: it works anywhere on any display (not just over the panel), at the
/// display's refresh rate, and needs no permission.
final class PointerTracker: NSObject {
    private let onTick: () -> Void
    private var link: CADisplayLink?

    init(onTick: @escaping () -> Void) {
        self.onTick = onTick
    }

    var isRunning: Bool { link != nil }

    /// Starts ticking with the refresh rate of the display `window` is on.
    func start(in window: NSWindow) {
        stop()
        let link = window.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()   // also releases the link's strong reference to us
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        onTick()
    }
}
