import AppKit
import SwiftUI

/// The borderless, transparent, non-activating panel the ring and toasts float in.
///
/// It joins every Space (other apps' full-screen Spaces included, as Halo runs as an accessory
/// app), sits at screen-saver level and never becomes key or main, so it never takes focus from
/// the frontmost app. `interceptor` sees every event first, so clicks can be decided by geometry
/// instead of SwiftUI hit-testing (unreliable in a window that is never key).
final class OverlayPanel: NSPanel {
    /// Sees every event before the panel dispatches it; return true to consume it.
    var interceptor: ((NSEvent) -> Bool)?

    init() {
        // `.nonactivatingPanel` must be in the style mask from the start; adding it later is unreliable.
        super.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true   // before `level`: setting it resets the level to .floating
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        isMovable = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
        becomesKeyOnlyIfNeeded = true
        worksWhenModal = true
        // Stay showable even after the user hides Halo (⌘H while a settings window is open).
        canHide = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if let interceptor, interceptor(event) { return }
        super.sendEvent(event)
    }
}

/// Hosts SwiftUI in an `OverlayPanel`: takes the first click (the panel is never key), never
/// resizes its window, ignores safe areas (no shift near the notch), and can report hover.
final class OverlayHostingView<Content: View>: NSHostingView<Content> {
    /// Called with true when the pointer enters the view and false when it leaves.
    var onHoverChange: ((Bool) -> Void)? {
        didSet { updateTrackingAreas() }
    }

    private var hoverArea: NSTrackingArea?

    required init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = []
        safeAreaRegions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        hoverArea = nil
        guard onHoverChange != nil else { return }
        // `.activeAlways`: the panel's app is never active, and the panel never key.
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if event.trackingArea === hoverArea { onHoverChange?(true) }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if event.trackingArea === hoverArea { onHoverChange?(false) }
    }
}
