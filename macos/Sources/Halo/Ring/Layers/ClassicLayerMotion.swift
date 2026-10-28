import Foundation

/// The live Classic ring's motion on Core Animation (SPEC §6 "Motion", tuned for the overlay),
/// at the user's animation speed: springs get `response ÷ speed` (stiffness × speed²), timed
/// curves and delays `÷ speed`; speed 0 makes everything instant. With Reduce Motion nothing
/// moves or scales: appear, dismiss and folders become 0.15 s cross-fades in place.
///
/// - Bloom: the hub grows first (0.5 → 1, spring 0.2 s / 0.8). Bubbles follow one by one,
///   clockwise from 12 o'clock, `RingMotion.bloomDelay` apart (20 ms, then 28 ms each), each
///   travelling out of the centre along its spoke while growing 0.25 → 1 and fading in, on a
///   spring of response 0.25 s, damping 0.72 (stiffness ≈ 632, damping ≈ 36): there after
///   ≈ 0.13 s, a 3.8 % overshoot at ≈ 0.18 s, settled by ≈ 0.28 s. Eight bubbles are in place by
///   ≈ 0.35 s and settled by ≈ 0.5 s.
/// - Collapse (dismiss, the other slots folding while one fires, folders folding): critically
///   damped, response 0.17 s, every bubble together; invisible by ≈ 0.15 s.
/// - Fan-out: folder children spring out of the folder along the arc (bloom spring), 25 ms
///   apart from the centre child outward; the root ring dims to 55 % over 0.2 s.
/// - Highlight: fill and glyph colour 0.12 s ease-out; tooltip in 0.12 s ease-out sliding 4 pt
///   outward, out 0.1 s.
/// - Execute: the chosen bubble swells to 1.1 in 70 ms and springs back (0.22 s / 0.72).
nonisolated struct ClassicLayerMotion: Equatable {
    var speed: Double
    var reduceMotion: Bool

    var isInstant: Bool { speed <= 0 }
    /// False when motion is replaced by cross-fades (Reduce Motion) or nothing.
    var moves: Bool { !isInstant && !reduceMotion }

    private func spring(_ response: Double, _ damping: Double) -> LayerCurve {
        if isInstant { return .instant }
        if reduceMotion { return crossFade }
        return .spring(LayerSpring(response: response / speed, damping: damping))
    }

    private func timed(_ duration: Double, _ easing: LayerEasing) -> LayerCurve {
        isInstant ? .instant : .timed(duration: duration / speed, easing: easing)
    }

    /// Reduce Motion's replacement for movement.
    private var crossFade: LayerCurve { timed(0.15, .easeInOut) }

    /// Seconds at the user's speed.
    func seconds(_ base: Double) -> Double { isInstant ? 0 : base / speed }

    // MARK: Ring

    var hubBloom: LayerCurve { spring(0.2, 0.8) }
    var bloom: LayerCurve { spring(0.25, 0.72) }
    var collapse: LayerCurve { spring(0.17, 1) }

    /// Delay before slot `index` of `count` starts to bloom (none for Reduce Motion's fade).
    func bloomDelay(index: Int, count: Int) -> Double {
        moves ? seconds(RingMotion.bloomDelay(index: index, count: count)) : 0
    }

    // MARK: Folders

    var fanOut: LayerCurve { bloom }
    var fanIn: LayerCurve { collapse }
    var dim: LayerCurve { reduceMotion ? crossFade : timed(0.2, .easeInOut) }

    /// Delay before folder child `index` of `count` starts to fan out: 25 ms per step away from
    /// the centre child.
    func fanDelay(index: Int, count: Int) -> Double {
        guard moves else { return 0 }
        let rank = (abs(Double(index) - Double(count - 1) / 2)).rounded(.down)
        return seconds(0.025 * rank)
    }

    // MARK: Highlight and labels

    var highlight: LayerCurve { reduceMotion ? crossFade : timed(0.12, .easeOut) }
    /// Folder tab retracting or returning (an image cross-dissolve), seconds.
    var tabFade: Double { seconds(0.12) }
    /// Hub state change (close/back/armed), seconds.
    var hubFade: Double { seconds(0.12) }
    var tooltipIn: LayerCurve { reduceMotion ? crossFade : timed(0.12, .easeOut) }
    var tooltipOut: LayerCurve { timed(reduceMotion ? 0.15 : 0.1, .easeOut) }
    /// How far a tooltip slides outward as it appears (× the ring's size multiplier).
    var tooltipSlide: Double { moves ? 4 : 0 }
    var chipFade: LayerCurve { timed(reduceMotion ? 0.15 : 0.1, .easeOut) }

    // MARK: Execute and reject

    var pulseSwell: LayerCurve { timed(0.07, .easeOut) }
    var pulseSettle: LayerCurve { spring(0.22, 0.72) }
    var pulseSwellDuration: Double { seconds(0.07) }
    var flashIn: LayerCurve { timed(0.05, .easeOut) }
    var flashOut: LayerCurve { timed(0.4, .easeIn) }
    var flashInDuration: Double { seconds(0.05) }
    /// The ring's rejection shake (three decaying oscillations), seconds; 0 = no shake.
    var shakeDuration: Double { moves ? seconds(0.3) : 0 }
}
