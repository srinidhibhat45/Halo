import Foundation

// CONTRACT — the overlay relies on these timings (when to order the panel out, how long the
// chosen slot flashes, how long a folder must be hovered). The ring renderer owns and tunes them
// to match its animations.
extension RingMotion {
    /// Seconds until the dismiss animation is visually complete at `speed` (0 = instant).
    ///
    /// Both themes dismiss with a critically damped spring of response 0.17 s (Classic:
    /// `ClassicLayerMotion.collapse` on the render server; Glass: `RingMotion.dismiss`), from
    /// wherever the ring is, so this holds when a dismiss interrupts an appear too. Classic
    /// bubbles are below 1 % opacity by ≈0.15 s and the hub, the last thing left, by ≈0.16 s;
    /// the Glass hub has shrunk to nothing by ≈0.16 s. Reduce Motion's 0.15 s cross-fade ends
    /// sooner.
    static func dismissDuration(speed: Double) -> TimeInterval { speed > 0 ? 0.16 / speed : 0 }

    /// Seconds the chosen slot pulses on its own before the ring dismisses: the pulse peaks at
    /// 70 ms while the other slots fold away, and the dismiss takes over as it eases back.
    static func flashDuration(speed: Double, reduceMotion: Bool) -> TimeInterval {
        speed > 0 && !reduceMotion ? min(0.08 / speed, 0.16) : 0
    }

    /// Hover time on a folder before it opens (tap and hold modes alike): long enough to pass
    /// over a folder on the way elsewhere, short enough to feel immediate.
    static let folderDwell: TimeInterval = 0.13
}
