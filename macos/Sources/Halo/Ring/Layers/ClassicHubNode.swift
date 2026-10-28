import QuartzCore

/// The Classic hub on the Core Animation ring: one pre-rendered image per look (close, back,
/// armed, holding, app badge) that cross-dissolves when the look changes, growing 0.5 → 1 and
/// fading in first on appear.
final class ClassicHubNode {
    let layer = CALayer()
    private var face: ClassicHubFace?
    private var style: ClassicArtStyle?
    private var reveal = Trajectory(0)

    init() {
        layer.contentsGravity = .center
        layer.minificationFilter = .trilinear
        layer.opacity = 0
    }

    /// Shows `face` centred at `rest` (on whole device pixels).
    func configure(_ face: ClassicHubFace, rest: CGPoint, style: ClassicArtStyle, now: Double, motion: ClassicLayerMotion) {
        layer.position = rest
        guard face != self.face || style != self.style else { return }
        // A new look cross-dissolves; a new style (scale, appearance) switches at once.
        let fade = self.face != nil && style == self.style ? motion.hubFade : 0
        self.face = face
        self.style = style
        let art = ClassicArtwork.shared.hub(face, style: style)
        layer.bounds = CGRect(origin: .zero, size: art.size)
        layer.contentsScale = style.pixelScale
        LayerAnimation.setContents(layer, art.image, fade: fade, now: now)
    }

    /// Grows in (1) or collapses (0) with `curve`.
    func setReveal(_ target: Double, curve: LayerCurve, now: Double, motion: ClassicLayerMotion) {
        guard target != reveal.target else { return }
        reveal.move(to: target, curve, now: now)
        let moves = motion.moves
        LayerAnimation.apply(reveal, to: layer, keyPath: "transform.scale", now: now) { p in
            NSNumber(value: moves ? 0.5 + 0.5 * max(p, 0) : 1)
        }
        LayerAnimation.apply(reveal, to: layer, keyPath: "opacity", now: now) { p in
            NSNumber(value: Float(moves ? Progress.smoothstep(0, 0.5, p) : Progress.clamped(p)))
        }
    }
}
