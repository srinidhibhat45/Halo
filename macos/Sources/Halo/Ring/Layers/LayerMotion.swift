import QuartzCore

// Analytic motion for layer animations. Every animated value of the Core Animation ring is a
// `Trajectory`: a chain of springs and timed curves that the view can evaluate at any moment
// (value and velocity), and that `LayerAnimation` hands to the render server as densely sampled
// keyframes. The render server plays them at the display's full rate whatever the main thread
// is doing, and because the view knows exactly where every value is (and how fast it is going),
// an interruption starts the next motion from there, velocity included.

/// A damped spring in SwiftUI's terms: `response` is the period of the undamped oscillation
/// (seconds) and `damping` the damping ratio (1 = critically damped; below 1 it overshoots).
/// With unit mass that is stiffness (2π / response)² and damping coefficient
/// 4π · damping / response; response 0.25 s at damping 0.72 is stiffness ≈ 632, damping ≈ 36.
nonisolated struct LayerSpring: Equatable {
    var response: Double
    var damping: Double

    /// Displacement from the rest point and velocity `t` seconds after leaving displacement `x0`
    /// with velocity `v0`.
    func state(x0: Double, v0: Double, at t: Double) -> (x: Double, v: Double) {
        let w0 = 2 * .pi / response
        let z = damping
        if z < 0.999 {
            let wd = w0 * (1 - z * z).squareRoot()
            let sigma = z * w0
            let a = x0, b = (v0 + sigma * x0) / wd
            let e = exp(-sigma * t), c = cos(wd * t), s = sin(wd * t)
            return (e * (a * c + b * s), e * ((b * wd - sigma * a) * c - (a * wd + sigma * b) * s))
        }
        if z <= 1.001 {
            let b = v0 + w0 * x0
            let e = exp(-w0 * t)
            return (e * (x0 + b * t), e * (b - w0 * (x0 + b * t)))
        }
        let root = w0 * (z * z - 1).squareRoot()
        let r1 = -z * w0 + root, r2 = -z * w0 - root
        let c2 = (v0 - r1 * x0) / (r2 - r1), c1 = x0 - c2
        let e1 = exp(r1 * t), e2 = exp(r2 * t)
        return (c1 * e1 + c2 * e2, c1 * r1 * e1 + c2 * r2 * e2)
    }

    /// Seconds until the motion stays within `tolerance` of rest (and nearly still).
    func settlingTime(x0: Double, v0: Double, tolerance: Double) -> Double {
        let step = 1.0 / 240
        var settled = 0.0
        var t = 0.0
        while t < 3 {
            let s = state(x0: x0, v0: v0, at: t)
            if abs(s.x) > tolerance || abs(s.v) > tolerance * 20 { settled = t + step }
            t += step
        }
        return settled
    }
}

/// Easing of a timed motion.
nonisolated enum LayerEasing: Equatable {
    case linear
    case easeIn
    case easeOut
    case easeInOut

    /// Progress at time fraction `u` (0 … 1).
    func value(_ u: Double) -> Double {
        switch self {
        case .linear: u
        case .easeIn: u * u * u
        case .easeOut: 1 - pow(1 - u, 3)
        case .easeInOut: u < 0.5 ? 4 * u * u * u : 1 - pow(-2 * u + 2, 3) / 2
        }
    }

    /// d(value)/du.
    func slope(_ u: Double) -> Double {
        switch self {
        case .linear: 1
        case .easeIn: 3 * u * u
        case .easeOut: 3 * pow(1 - u, 2)
        case .easeInOut: u < 0.5 ? 12 * u * u : 3 * pow(-2 * u + 2, 2)
        }
    }
}

/// How a value moves to its next target.
nonisolated enum LayerCurve: Equatable {
    /// A spring, carrying over the velocity the value has when it starts.
    case spring(LayerSpring)
    /// A fixed-duration curve (velocity is not carried over).
    case timed(duration: Double, easing: LayerEasing)
    /// No motion: the value is at its target at once.
    case instant
}

/// One motion of a value from `from` to `to`, starting at `start` (layer time).
nonisolated struct MotionSegment {
    let start: Double
    let from: Double
    let to: Double
    let velocity: Double
    let curve: LayerCurve
    /// When the motion is (within a hair of) done.
    let end: Double

    /// Precision a spring must settle to: well below a pixel and below 1 % of any opacity.
    static let tolerance = 0.0004

    init(start: Double, from: Double, to: Double, velocity: Double, curve: LayerCurve) {
        self.start = start
        self.from = from
        self.to = to
        self.velocity = velocity
        self.curve = curve
        switch curve {
        case .spring(let spring):
            end = start + spring.settlingTime(x0: from - to, v0: velocity, tolerance: Self.tolerance)
        case .timed(let duration, _):
            end = start + max(duration, 0)
        case .instant:
            end = start
        }
    }

    func value(at t: Double) -> Double {
        let dt = t - start
        guard dt > 0 else { return from }
        guard t < end else { return to }
        switch curve {
        case .spring(let spring): return to + spring.state(x0: from - to, v0: velocity, at: dt).x
        case .timed(let duration, let easing): return from + (to - from) * easing.value(dt / duration)
        case .instant: return to
        }
    }

    func velocity(at t: Double) -> Double {
        let dt = t - start
        guard dt >= 0, t < end else { return 0 }
        switch curve {
        case .spring(let spring): return spring.state(x0: from - to, v0: velocity, at: dt).v
        case .timed(let duration, let easing): return (to - from) * easing.slope(dt / duration) / duration
        case .instant: return 0
        }
    }
}

/// A value's motion over time: a chain of segments, each starting from wherever (and as fast
/// as) the value is going when it begins. Times are in the ring layer's clock.
nonisolated struct Trajectory {
    /// The value before the first segment (or at rest when there is none).
    private var base: Double
    private var segments: [MotionSegment] = []

    init(_ value: Double) {
        base = value
    }

    /// Where the value ends up.
    var target: Double { segments.last?.to ?? base }
    /// When the value stops moving.
    var end: Double { segments.last?.end ?? -.infinity }

    func value(at t: Double) -> Double {
        guard let i = segments.lastIndex(where: { $0.start <= t }) else { return segments.first?.from ?? base }
        return segments[i].value(at: t)
    }

    func velocity(at t: Double) -> Double {
        guard let i = segments.lastIndex(where: { $0.start <= t }) else { return 0 }
        return segments[i].velocity(at: t)
    }

    /// Puts the value at `value` at once.
    mutating func jump(to value: Double) {
        base = value
        segments.removeAll()
    }

    /// Moves the value toward `target` with `curve`, starting `delay` seconds after `now` from
    /// wherever it is by then (until then it carries on as it was going).
    mutating func move(to target: Double, _ curve: LayerCurve, now: Double, delay: Double = 0) {
        if curve == .instant {
            jump(to: target)
            return
        }
        let start = now + max(delay, 0)
        let from = value(at: start), velocity = velocity(at: start)
        // Drop what has already been superseded and anything that would have started later.
        if let current = segments.lastIndex(where: { $0.start <= now }), current > 0 {
            segments.removeFirst(current)
        }
        segments.removeAll { $0.start >= start }
        if segments.isEmpty { base = from }
        if abs(from - target) < MotionSegment.tolerance, abs(velocity) < MotionSegment.tolerance {
            if segments.isEmpty { base = target }
            return
        }
        segments.append(MotionSegment(start: start, from: from, to: target, velocity: velocity, curve: curve))
    }
}

/// Hands trajectories to the render server.
enum LayerAnimation {
    /// Keyframes per second. Linear interpolation between samples this dense is exact to well
    /// under a pixel at any display rate, 120 Hz included.
    static let samplesPerSecond = 240.0

    /// Sets `keyPath` of `layer` to where `trajectory` ends (mapped through `value`) and, while it
    /// still moves after `now`, adds keyframes that play the way there. Replaces any earlier
    /// animation of `keyPath`, which the new one continues seamlessly. Call inside a transaction
    /// with actions disabled.
    static func apply(_ trajectory: Trajectory, to layer: CALayer, keyPath: String, now: Double, value: (Double) -> Any) {
        layer.setValue(value(trajectory.target), forKeyPath: keyPath)
        let duration = trajectory.end - now
        guard duration > 0.001 else {
            layer.removeAnimation(forKey: keyPath)
            return
        }
        let count = Int((duration * samplesPerSecond).rounded(.up)) + 1
        var values: [Any] = []
        values.reserveCapacity(count)
        for i in 0..<(count - 1) {
            values.append(value(trajectory.value(at: now + duration * Double(i) / Double(count - 1))))
        }
        values.append(value(trajectory.target))
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.beginTime = now
        animation.duration = duration
        animation.calculationMode = .linear
        animation.fillMode = .backwards
        layer.add(animation, forKey: keyPath)
    }

    /// Replaces `layer`'s image, cross-dissolving from the old one over `duration` seconds.
    static func setContents(_ layer: CALayer, _ image: CGImage?, fade duration: Double, now: Double) {
        let old = layer.contents
        layer.contents = image
        guard duration > 0, let old, let image, (old as AnyObject) !== image else {
            layer.removeAnimation(forKey: "contents")
            return
        }
        let animation = CABasicAnimation(keyPath: "contents")
        animation.fromValue = old
        animation.toValue = image
        animation.beginTime = now
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        animation.fillMode = .backwards
        layer.add(animation, forKey: "contents")
    }

    /// Runs `changes` with implicit layer animations off.
    static func withoutActions(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }
}
