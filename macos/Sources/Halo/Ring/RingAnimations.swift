import HaloCore
import SwiftUI

/// Every SwiftUI animation the ring uses (SPEC §6 "Motion"), scaled by the user's animation
/// speed. (The live Classic ring runs on Core Animation with `ClassicLayerMotion`, which shares
/// `bloomDelay` and the dismiss timing.)
///
/// Motion is progress-driven: the renderer animates a few numbers (appear, fan, highlight,
/// pulse) with these springs and derives all geometry from them on every frame. A spring that is
/// retargeted mid-flight keeps its velocity, so every motion can be interrupted and reversed
/// smoothly. `speed` 0 means no animation; Reduce Motion keeps everything in place and turns
/// appear, dismiss, fan and highlight into short cross-fades (callers check `allowsMovement`
/// before moving or resizing anything).
struct RingMotion: Equatable {
    /// 0.5 (slow) … 2 (fast); 0 disables animation.
    var speed: Double
    var reduceMotion: Bool

    var isInstant: Bool { speed <= 0 }
    /// False when motion should be replaced by a cross-fade (Reduce Motion) or nothing.
    var allowsMovement: Bool { !isInstant && !reduceMotion }

    /// `base` seconds at the user's speed.
    func duration(_ base: Double) -> Double { isInstant ? 0 : base / speed }

    /// The Reduce Motion cross-fade, or nil when animations are off.
    private var crossFade: Animation? { isInstant ? nil : .easeInOut(duration: 0.15) }

    /// A spring with `response` seconds (at speed 1) and `damping`, or the Reduce Motion
    /// cross-fade.
    private func spring(_ response: Double, _ damping: Double) -> Animation? {
        if isInstant { return nil }
        if reduceMotion { return crossFade }
        return .spring(response: response / speed, dampingFraction: damping)
    }

    /// The ring opening: ≈96 % there after 0.2 s, then a ≈1 % overshoot settles; no wobble.
    var appear: Animation? { spring(0.34, 0.82) }
    /// The ring closing, and the other slots folding away while the chosen one fires: faster
    /// and critically damped, so it never springs back. Visually gone after `dismissDuration`.
    var dismiss: Animation? { spring(0.17, 1) }
    /// Glass appear: segment `index` of `count` grows out of the hub `bloomDelay` after the hub
    /// starts, so the segments arrive one after another clockwise from 12 o'clock. Reopening
    /// before the ring has collapsed (`staggered` false) reverses every segment at once.
    func glassSegmentAppear(index: Int, count: Int, staggered: Bool) -> Animation? {
        guard let base = spring(0.28, 0.8) else { return nil }
        guard staggered, !reduceMotion else { return base }
        return base.delay(Self.bloomDelay(index: index, count: count) / speed)
    }

    /// Seconds (at speed 1) after the hub at which slot `index` of `count` starts to bloom:
    /// 20 ms for slot 0, then 28 ms per slot clockwise, spread over at most 0.24 s in all.
    nonisolated static func bloomDelay(index: Int, count: Int) -> Double {
        let step = min(0.028, 0.22 / Double(max(count - 1, 1)))
        return 0.02 + Double(index) * step
    }
    /// Classic highlight: the bubble's fill and glyph colour.
    var classicHighlight: Animation? { spring(0.19, 1) }
    /// Glass highlight: the tint and the segment's outward growth.
    var glassHighlight: Animation? { spring(0.24, 0.8) }
    /// Folder children fanning out of their folder.
    var fanOut: Animation? { spring(0.36, 0.84) }
    /// Folder children folding back into their folder.
    var fanIn: Animation? { spring(0.24, 1) }
    /// The root ring dimming behind a fanned-out folder, and brightening again.
    var dim: Animation? { spring(0.3, 1) }
    /// A Classic tooltip sliding out from its bubble.
    var labelIn: Animation? { spring(0.24, 0.9) }
    /// A tooltip or hub title leaving (quicker than it came).
    var labelOut: Animation? { isInstant ? nil : .easeOut(duration: (reduceMotion ? 0.15 : 0.1) / speed) }
    /// Editor selection, drop-target glow and other small state changes.
    var emphasis: Animation? { spring(0.26, 0.82) }
    /// An icon or title replaced in place (editor drop).
    var contentSwap: Animation? { isInstant ? nil : .easeInOut(duration: 0.15 / speed) }

    /// Editor build-in: the hub first, then slots clockwise from 12 o'clock, 33 ms apart.
    func buildIn(index: Int?) -> Animation? {
        if isInstant { return nil }
        if reduceMotion { return crossFade }
        guard let index else { return .spring(response: 0.3 / speed, dampingFraction: 0.84) }
        return .spring(response: 0.34 / speed, dampingFraction: 0.84).delay((0.1 + Double(index) * 0.033) / speed)
    }

    /// Empty-slot rejection shake (three oscillations).
    var shake: Animation? { allowsMovement ? .linear(duration: 0.3 / speed) : nil }
}

// MARK: - Progress math

/// Easing helpers for progress-driven motion. Progress may briefly exceed 1 while a spring
/// settles; these keep that overshoot where it reads as a natural settle.
nonisolated enum Progress {
    static func clamped(_ x: Double) -> Double { min(max(x, 0), 1) }

    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    /// Hermite smoothstep of `x` between `edge0` and `edge1` (0 below, 1 above).
    static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = clamped((x - edge0) / (edge1 - edge0))
        return t * t * (3 - 2 * t)
    }

    /// `progress` starting late: 0 until it passes `delay`, then rising to reach 1 together
    /// with it (and overshooting with it, slightly amplified).
    static func delayed(_ progress: Double, by delay: Double) -> Double {
        delay <= 0 ? progress : max(0, (progress - delay) / (1 - delay))
    }

    /// Progress by which each rank of folder children starts later than the centre child: a
    /// slight stagger from the centre outward (reversed when folding).
    static let fanStagger = 0.05

    /// Stagger delay of folder child `index` of `count`: by distance from the middle child.
    static func fanDelay(index: Int, count: Int) -> Double {
        (abs(Double(index) - Double(count - 1) / 2)).rounded(.down) * fanStagger
    }
}

// MARK: - Snapshot freeze

/// Holds the SwiftUI ring's motion at fixed progress values, so the snapshot renderer can draw
/// any frame of an animation. nil fields animate normally; the app never sets it. (The Core
/// Animation ring is frozen through its layer clock instead.)
struct RingMotionFreeze: Equatable {
    /// Progress of the open folder's fan (0 folded into the folder … 1 fanned out).
    var fan: Double?
    /// Strength of the highlight on the highlighted slot (0 … 1).
    var highlight: Double?
}

extension RingMotionFreeze {
    /// `state` with the frozen highlight strength applied to a hover highlight (an open
    /// folder's fill is not a hover and stays).
    func applied(to state: SlotDrawState) -> SlotDrawState {
        guard let highlight, state.highlight > 0, !state.isOpenFolder else { return state }
        var state = state
        state.highlight *= highlight
        return state
    }
}

private struct RingMotionFreezeKey: EnvironmentKey {
    static let defaultValue = RingMotionFreeze()
}

extension EnvironmentValues {
    var ringMotionFreeze: RingMotionFreeze {
        get { self[RingMotionFreezeKey.self] }
        set { self[RingMotionFreezeKey.self] = newValue }
    }
}

// MARK: - Highlight ink

/// A glyph changing from its idle to its highlighted colour without the dip of a plain
/// cross-fade: the highlighted copy fades in over the idle one, which leaves only once it is
/// covered, so the glyph reads as a blend of both colours rather than half transparent. The
/// switch happens while the fill behind passes mid-tone (`litStrength`), keeping the glyph
/// legible against it throughout.
struct InkBlend<Idle: View, Lit: View>: View, Animatable {
    /// Highlight strength (0 … 1).
    var highlight: Double
    let idle: Idle
    let lit: Lit

    var animatableData: Double {
        get { highlight }
        set { highlight = newValue }
    }

    /// How far the glyph has turned to its highlighted colour at `highlight`.
    nonisolated static func litStrength(_ highlight: Double) -> Double {
        Progress.smoothstep(0.25, 0.6, highlight)
    }

    var body: some View {
        ZStack {
            idle.opacity(1 - Progress.clamped((highlight - 0.6) / 0.4))
            lit.opacity(Self.litStrength(highlight))
        }
    }
}

// MARK: - Execute pulse

/// Feeds `content` the chosen slot's "fire" pulse, 0 → 1 → 0: a 70 ms swell, then a soft
/// spring back (the dismiss starts meanwhile). Glass grows the segment's shape by it. Zero
/// throughout when nothing fires or motion is reduced.
struct ExecutePulse<Content: View>: View {
    var isExecuting: Bool
    var motion: RingMotion
    @ViewBuilder var content: (Double) -> Content

    var body: some View {
        let fires = isExecuting && motion.allowsMovement
        KeyframeAnimator(initialValue: 0.0, trigger: isExecuting) { pulse in
            content(pulse)
        } keyframes: { _ in
            KeyframeTrack(\.self) {
                if fires {
                    CubicKeyframe(1, duration: motion.duration(0.07))
                    SpringKeyframe(0, duration: motion.duration(0.26), spring: Spring(response: motion.duration(0.22), dampingRatio: 0.72))
                } else {
                    MoveKeyframe(0)
                }
            }
        }
    }
}

// MARK: - Reject flash

/// Briefly tints a rejected (empty) slot red; `token` changes on every rejection of this slot.
struct RejectFlash<S: Shape>: ViewModifier {
    var token: Int
    var shape: S
    var motion: RingMotion

    func body(content: Content) -> some View {
        let active = token > 0 && !motion.isInstant
        content.keyframeAnimator(initialValue: 0.0, trigger: token) { view, strength in
            view.overlay {
                shape.fill(Color.red.opacity(0.22 * strength))
                    .overlay { shape.stroke(Color.red.opacity(0.85 * strength), lineWidth: 1.5) }
            }
        } keyframes: { _ in
            KeyframeTrack(\.self) {
                if active {
                    LinearKeyframe(1.0, duration: motion.duration(0.05), timingCurve: .easeOut)
                    LinearKeyframe(0.0, duration: motion.duration(0.4), timingCurve: .easeIn)
                } else {
                    MoveKeyframe(0.0)
                }
            }
        }
    }
}
