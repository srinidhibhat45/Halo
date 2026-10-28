import AppKit

/// Turns scroll events into whole adjustment steps, like Logitech's adjustable bubbles: one step
/// per mouse-wheel notch, or one per `preciseStep` points of trackpad / smooth scrolling.
/// Positive steps mean up (wheel away from you, fingers up), whatever the natural-scrolling setting.
struct ScrollStepper {
    var preciseStep: CGFloat = 14
    private var accumulated: CGFloat = 0

    mutating func reset() {
        accumulated = 0
    }

    mutating func steps(for event: NSEvent) -> Int {
        // Momentum after a trackpad flick would keep adjusting long after the fingers lifted.
        guard event.momentumPhase.isEmpty else { return 0 }
        let delta = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
        guard delta != 0 else { return 0 }
        guard event.hasPreciseScrollingDeltas else { return delta > 0 ? 1 : -1 }
        if accumulated != 0, (accumulated > 0) != (delta > 0) { accumulated = 0 }
        accumulated += delta
        let steps = Int(accumulated / preciseStep)
        accumulated -= CGFloat(steps) * preciseStep
        return steps
    }
}
