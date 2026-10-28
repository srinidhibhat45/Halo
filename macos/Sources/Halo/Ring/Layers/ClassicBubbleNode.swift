import HaloCore
import QuartzCore
import SwiftUI

/// One Classic bubble of the Core Animation ring (a root slot or a folder child) and its labels.
///
/// Layers: `travel` (position, appear scale and fade) holds `face` (root dimming and the execute
/// pulse, flattened so a fade never shows the shadow through the fill), which stacks the
/// pre-rendered pieces in `ClassicBubbleParts` order. `labels` (tooltip and chip) goes in the
/// view's label layer, above every bubble and the hub, and fades with the bubble.
///
/// Every animated value is a `Trajectory`; a new target starts from wherever the value is at
/// that moment, with its velocity, so any change can interrupt any other without a jump.
final class ClassicBubbleNode {
    /// Where the bubble rests and where it blooms from.
    struct Placement: Equatable {
        /// Direction from the ring centre (y-down radians); the tab and dot face it.
        var angle: Double
        /// Resting position on whole device pixels (where SwiftUI would round it), relative to
        /// the ring's container (y-down).
        var rest: CGPoint
        /// Where the bloom starts (polar, around the ring centre).
        var origin: PolarPoint
        var startScale: CGFloat
        /// Labels fade in over the last part of the bloom, from this progress on.
        var labelFadeFrom: Double

        /// The bubble's centre at bloom progress `p`: angle and radius interpolate, so it travels
        /// along its spoke (root slots) or along the arc (folder children).
        func point(at p: Double) -> CGPoint {
            let restAngle = Double(atan2(rest.y, rest.x))
            let restRadius = (rest.x * rest.x + rest.y * rest.y).squareRoot()
            var fromAngle = origin.radius > 0.01 ? origin.angle : restAngle
            // Take the short way round.
            while fromAngle - restAngle > .pi { fromAngle -= 2 * .pi }
            while restAngle - fromAngle > .pi { fromAngle += 2 * .pi }
            let t = max(p, 0)
            let angle = Progress.lerp(fromAngle, restAngle, t)
            let radius = Progress.lerp(origin.radius, restRadius, t)
            return CGPoint(x: CGFloat(cos(angle)) * radius, y: CGFloat(sin(angle)) * radius)
        }

        func scale(at p: Double) -> CGFloat { Progress.lerp(startScale, 1, max(p, 0)) }
    }

    let travel = CALayer()
    let labels = CALayer()
    private let face = CALayer()
    private let disc = CALayer()
    private let tile = CALayer()
    private let hairline = CALayer()
    private let idleInk = CALayer()
    private let litInk = CALayer()
    private let artwork = CALayer()
    private let outline = CALayer()
    private let number = CALayer()
    private let emptyCold = CALayer()
    private let emptyHot = CALayer()
    private let flashLayer = CALayer()
    private let tooltip = CALayer()
    private let chip = CALayer()

    private(set) var slotFace: SlotFace?
    private(set) var placement: Placement?
    private var showsTab = true
    private var style: ClassicArtStyle?
    private var numberValue: Int?
    private var tooltipPlacement: RadialLabelPlacement?
    private var chipPlacement: RadialLabelPlacement?

    /// Bloom progress: 0 collapsed into its origin … 1 at rest (briefly above while settling).
    private(set) var reveal = Trajectory(0)
    private var highlight = Trajectory(0)
    private var dim = Trajectory(0)
    private var pulse = Trajectory(0)
    private var flash = Trajectory(0)
    private var numberShown = Trajectory(1)
    private var tooltipShown = Trajectory(0)
    private var tooltipSlide = Trajectory(1)
    private var chipShown = Trajectory(0)

    init() {
        for layer in [travel, face, disc, tile, hairline, idleInk, litInk, artwork, outline, number, emptyCold, emptyHot, flashLayer, tooltip, chip, labels] {
            layer.contentsGravity = .center
            layer.minificationFilter = .trilinear
        }
        travel.allowsGroupOpacity = false
        face.allowsGroupOpacity = true
        labels.allowsGroupOpacity = false
        travel.addSublayer(face)
        for piece in [disc, tile, hairline, idleInk, litInk, artwork, outline, emptyCold, emptyHot, flashLayer, number] {
            face.addSublayer(piece)
        }
        labels.addSublayer(chip)
        labels.addSublayer(tooltip)
        for hidden in [travel, labels, tooltip, chip, flashLayer] { hidden.opacity = 0 }
    }

    /// True once the bubble has collapsed for good (nothing left to draw).
    func isGone(at now: Double) -> Bool { reveal.target == 0 && reveal.end <= now }

    func removeFromRing() {
        travel.removeFromSuperlayer()
        labels.removeFromSuperlayer()
    }

    // MARK: Content

    /// Shows `face` at `placement` in `style`; images change at once (content only changes
    /// while a ring is being set up). A move re-plays the bloom along the new path.
    func configure(_ face: SlotFace, placement: Placement, number: Int?, style: ClassicArtStyle, now: Double, motion: ClassicLayerMotion) {
        let moved = placement != self.placement
        let redraw = face != slotFace || moved || style != self.style
        slotFace = face
        self.placement = placement
        self.style = style
        if redraw {
            setArt(ClassicArtwork.shared.bubble(face, angle: placement.angle, showsTab: showsTab, style: style), fade: 0, now: now)
            tooltipPlacement = nil
            chipPlacement = nil
            tooltip.contents = nil
            chip.contents = nil
        }
        if redraw || number != numberValue {
            numberValue = number
            // Without a number the last badge stays in place while it fades out.
            if let value = number {
                self.number.contents = ClassicArtwork.shared.number(value, angle: placement.angle, style: style)
            }
            numberShown.move(to: number == nil ? 0 : 1, redraw ? .instant : motion.dim, now: now)
            LayerAnimation.apply(numberShown, to: self.number, keyPath: "opacity", now: now) { NSNumber(value: Float($0)) }
        }
        if moved { applyReveal(now: now, motion: motion) }
    }

    /// Shows the folder tab (closed folder) or hides it (open folder), cross-dissolving.
    func setShowsTab(_ shows: Bool, now: Double, motion: ClassicLayerMotion) {
        guard shows != showsTab else { return }
        showsTab = shows
        guard let slotFace, slotFace.kind == .folder, let placement, let style else { return }
        setArt(ClassicArtwork.shared.bubble(slotFace, angle: placement.angle, showsTab: shows, style: style), fade: motion.tabFade, now: now)
    }

    private func setArt(_ art: ClassicBubbleArt, fade: Double, now: Double) {
        let bounds = CGRect(origin: .zero, size: art.size)
        travel.bounds = bounds
        face.frame = bounds
        let pieces: [(CALayer, CGImage?)] = [
            (disc, art.disc), (tile, art.tile), (hairline, art.hairline), (idleInk, art.idleInk), (litInk, art.litInk),
            (artwork, art.artwork), (outline, art.outline), (emptyCold, art.emptyCold), (emptyHot, art.emptyHot), (flashLayer, art.flash),
        ]
        for (layer, image) in pieces {
            layer.frame = bounds
            layer.contentsScale = style?.pixelScale ?? 2
            LayerAnimation.setContents(layer, image, fade: fade, now: now)
            layer.isHidden = image == nil
        }
        number.frame = bounds
        number.contentsScale = style?.pixelScale ?? 2
        applyHighlight(now: now)
    }

    // MARK: Motion

    /// Blooms out (1) or collapses (0) with `curve`, starting after `delay`.
    func setReveal(_ target: Double, curve: LayerCurve, delay: Double = 0, now: Double, motion: ClassicLayerMotion) {
        guard target != reveal.target else { return }
        reveal.move(to: target, curve, now: now, delay: delay)
        applyReveal(now: now, motion: motion)
    }

    /// How far the bubble has bloomed now (0 … 1).
    func revealProgress(at now: Double) -> Double { Progress.clamped(reveal.value(at: now)) }

    private func applyReveal(now: Double, motion: ClassicLayerMotion) {
        guard let placement else { return }
        let moves = motion.moves
        LayerAnimation.apply(reveal, to: travel, keyPath: "position", now: now) { p in
            NSValue(point: moves ? placement.point(at: p) : placement.rest)
        }
        LayerAnimation.apply(reveal, to: travel, keyPath: "transform.scale", now: now) { p in
            NSNumber(value: Double(moves ? placement.scale(at: p) : 1))
        }
        LayerAnimation.apply(reveal, to: travel, keyPath: "opacity", now: now) { p in
            NSNumber(value: Float(moves ? Progress.smoothstep(0, 0.5, p) : Progress.clamped(p)))
        }
        LayerAnimation.apply(reveal, to: labels, keyPath: "opacity", now: now) { p in
            NSNumber(value: Float(Progress.smoothstep(placement.labelFadeFrom, 1, p)))
        }
    }

    /// Highlight strength: 1 for the hover highlight, an open folder or the chosen slot.
    func setHighlight(_ target: Double, now: Double, motion: ClassicLayerMotion) {
        guard target != highlight.target else { return }
        highlight.move(to: target, motion.highlight, now: now)
        applyHighlight(now: now)
    }

    /// The tile fades in under a glyph that turns white as the fill passes mid-tone (`InkBlend`).
    private func applyHighlight(now: Double) {
        let isAppIcon = slotFace?.isAppIcon ?? false
        let opacity = { (f: @escaping (Double) -> Double) in { (h: Double) -> Any in NSNumber(value: Float(f(h))) } }
        LayerAnimation.apply(highlight, to: tile, keyPath: "opacity", now: now, value: opacity { Progress.clamped($0) })
        LayerAnimation.apply(highlight, to: hairline, keyPath: "opacity", now: now, value: opacity { isAppIcon ? Progress.clamped($0) : 1 })
        LayerAnimation.apply(highlight, to: idleInk, keyPath: "opacity", now: now, value: opacity { 1 - Progress.clamped(($0 - 0.6) / 0.4) })
        LayerAnimation.apply(highlight, to: litInk, keyPath: "opacity", now: now, value: opacity { InkBlend<EmptyView, EmptyView>.litStrength($0) })
        LayerAnimation.apply(highlight, to: outline, keyPath: "opacity", now: now, value: opacity { Progress.clamped($0) })
        LayerAnimation.apply(highlight, to: emptyHot, keyPath: "opacity", now: now, value: opacity { Progress.clamped($0) })
        LayerAnimation.apply(highlight, to: emptyCold, keyPath: "opacity", now: now, value: opacity { 1 - Progress.clamped($0) })
    }

    /// Dims to 55 % (a root slot behind a fanned-out folder) or back.
    func setDimmed(_ dimmed: Bool, now: Double, motion: ClassicLayerMotion) {
        let target: Double = dimmed ? 1 : 0
        guard target != dim.target else { return }
        dim.move(to: target, motion.dim, now: now)
        LayerAnimation.apply(dim, to: face, keyPath: "opacity", now: now) { NSNumber(value: Float(1 - 0.45 * $0)) }
    }

    /// The chosen slot's pulse: 1 → 1.1 in 70 ms, then a soft spring back.
    func firePulse(now: Double, motion: ClassicLayerMotion) {
        guard motion.moves else { return }
        pulse.move(to: 1, motion.pulseSwell, now: now)
        pulse.move(to: 0, motion.pulseSettle, now: now, delay: motion.pulseSwellDuration)
        LayerAnimation.apply(pulse, to: face, keyPath: "transform.scale", now: now) { NSNumber(value: 1 + 0.1 * $0) }
    }

    /// An empty slot's red rejection flash.
    func flashRejection(now: Double, motion: ClassicLayerMotion) {
        guard !motion.isInstant else { return }
        flash.move(to: 1, motion.flashIn, now: now)
        flash.move(to: 0, motion.flashOut, now: now, delay: motion.flashInDuration)
        LayerAnimation.apply(flash, to: flashLayer, keyPath: "opacity", now: now) { NSNumber(value: Float(Progress.clamped($0))) }
    }

    // MARK: Labels

    /// Shows the hover tooltip at `placement` (sliding out from the bubble) or hides it.
    func setTooltip(_ placement: RadialLabelPlacement?, now: Double, motion: ClassicLayerMotion) {
        guard let placement, let slotFace, let style else {
            guard tooltipShown.target != 0 else { return }
            tooltipShown.move(to: 0, motion.tooltipOut, now: now)
            LayerAnimation.apply(tooltipShown, to: tooltip, keyPath: "opacity", now: now) { NSNumber(value: Float($0)) }
            return
        }
        if placement != tooltipPlacement {
            tooltipPlacement = placement
            place(tooltip, title: slotFace.title, style: .tooltip, placement: placement, art: style)
        }
        guard tooltipShown.target != 1 else { return }
        // A tooltip arriving from nothing slides out; one coming back mid-fade just fades back.
        if tooltipShown.value(at: now) < 0.05 { tooltipSlide.jump(to: 0) }
        tooltipShown.move(to: 1, motion.tooltipIn, now: now)
        tooltipSlide.move(to: 1, motion.tooltipIn, now: now)
        LayerAnimation.apply(tooltipShown, to: tooltip, keyPath: "opacity", now: now) { NSNumber(value: Float($0)) }
        let rest = tooltip.position
        let direction = Self.outward(placement)
        let distance = motion.tooltipSlide * Double(style.unit)
        LayerAnimation.apply(tooltipSlide, to: tooltip, keyPath: "position", now: now) { s in
            let back = CGFloat((1 - s) * distance)
            return NSValue(point: CGPoint(x: rest.x - direction.x * back, y: rest.y - direction.y * back))
        }
    }

    /// Shows the caption chip (`labelMode == .always`) at `placement`, or hides it.
    func setChip(_ placement: RadialLabelPlacement?, now: Double, motion: ClassicLayerMotion) {
        if let placement, let slotFace, let style, placement != chipPlacement {
            chipPlacement = placement
            place(chip, title: slotFace.title, style: .chip, placement: placement, art: style)
        }
        let target: Double = placement == nil ? 0 : 1
        guard target != chipShown.target else { return }
        chipShown.move(to: target, motion.chipFade, now: now)
        LayerAnimation.apply(chipShown, to: chip, keyPath: "opacity", now: now) { NSNumber(value: Float($0)) }
    }

    /// Puts `layer` at `placement` (on whole device pixels) with its image.
    private func place(_ layer: CALayer, title: String, style labelStyle: ClassicLabel.Style, placement: RadialLabelPlacement, art: ClassicArtStyle) {
        let label = ClassicArtwork.shared.label(title, style: labelStyle, placement: placement, style: art)
        layer.bounds = CGRect(origin: .zero, size: label.size)
        layer.position = art.snapped(CGPoint(x: placement.center.x + centreOffset.x, y: placement.center.y + centreOffset.y))
        layer.contentsScale = art.pixelScale
        layer.contents = label.image
    }

    /// How far the ring centre lies from the label container's origin (less than a pixel; set
    /// by the view).
    var centreOffset = CGPoint.zero

    /// Unit vector from the bubble to its label's centre.
    private static func outward(_ placement: RadialLabelPlacement) -> CGPoint {
        let dx = placement.size.width / 2 - placement.target.x, dy = placement.size.height / 2 - placement.target.y
        let length = max((dx * dx + dy * dy).squareRoot(), 0.001)
        return CGPoint(x: dx / length, y: dy / length)
    }
}
