import HaloCore
import SwiftUI

/// A `RingView` in `.preview` mode, fitted into a square of `side` points, that follows
/// `settings` and `ring` as they change.
///
/// With `showsSizeChanges`, the fit is computed for the largest ring size, so changing the
/// ring size visibly grows and shrinks the preview instead of being scaled away. With
/// `followsPointer`, pointing at the preview highlights slots like the real ring does.
struct RingPreview: View {
    let ring: Ring
    let settings: AppSettings
    /// The slot highlighted when the pointer isn't over the preview.
    var restingHighlight: Int?
    let side: CGFloat
    var showsSizeChanges = false
    var followsPointer = false

    @ViewState private var model: RingViewModel
    @ViewState private var pointerHighlight: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(ring: Ring, settings: AppSettings, restingHighlight: Int? = nil, side: CGFloat,
         showsSizeChanges: Bool = false, followsPointer: Bool = false) {
        self.ring = ring
        self.settings = settings
        self.restingHighlight = restingHighlight
        self.side = side
        self.showsSizeChanges = showsSizeChanges
        self.followsPointer = followsPointer
        let model = RingViewModel(mode: .preview, ring: ring, settings: settings)
        model.highlighted = restingHighlight
        _model = ViewState(initialValue: model)
    }

    var body: some View {
        let metrics = model.metrics
        let fit = fitScale(for: metrics)
        RingView(model: model)
            .frame(width: metrics.canvasSide, height: metrics.canvasSide)
            .scaleEffect(fit)
            .frame(width: metrics.canvasSide * fit, height: metrics.canvasSide * fit)
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard followsPointer else { return }
                switch phase {
                case .active(let point):
                    pointerHighlight = slot(at: point, metrics: metrics, fit: fit)
                case .ended:
                    pointerHighlight = nil
                }
                model.highlighted = pointerHighlight ?? restingHighlight
            }
            .onChange(of: settings) { _, newValue in
                withAnimation(changeAnimation(for: newValue)) { model.apply(newValue) }
            }
            .onChange(of: ring) { _, newValue in
                // The slot count may have changed: never keep a highlight past the end.
                model.ring = newValue
                pointerHighlight = nil
                model.highlighted = restingHighlight
            }
            .onChange(of: restingHighlight) { _, newValue in
                if pointerHighlight == nil { model.highlighted = newValue }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Ring preview")
            .accessibilityValue(accessibilityDescription)
    }

    /// Scale that fits the drawn ring (or, with `showsSizeChanges`, the largest ring) into
    /// `side`. The canvas's outer padding (room for shadows and glow) may spill past `side`.
    private func fitScale(for metrics: RingMetrics) -> CGFloat {
        let reference = showsSizeChanges
            ? RingMetrics(theme: model.theme, scale: AppSettings.ringScaleRange.upperBound, slotCount: model.ring.slotCount)
            : metrics
        let extent = (reference.outerRadius * reference.highlightScale + 12) * 2
        guard extent > 0 else { return 1 }
        return min(1, side / extent)
    }

    /// The slot under `point` (in this view's space), using the same geometry as the overlay.
    private func slot(at point: CGPoint, metrics: RingMetrics, fit: CGFloat) -> Int? {
        let dx = Double(point.x - side / 2)
        let dy = Double(point.y - side / 2)
        return model.geometry.slot(
            dx: dx, dy: dy,
            deadZone: Double(metrics.tapDeadZone * fit),
            maxRadius: Double(metrics.maxHitRadius * fit),
            current: model.highlighted,
            hysteresis: metrics.hysteresis
        )
    }

    private func changeAnimation(for settings: AppSettings) -> Animation? {
        guard !reduceMotion, settings.animationSpeed > 0 else { return nil }
        return .snappy(duration: 0.3 / settings.animationSpeed)
    }

    private var accessibilityDescription: String {
        let theme = settings.theme == .classic ? "Classic" : "Glass"
        let size = Int((settings.ringScale * 100).rounded())
        return "\(theme) theme, \(size) percent size, \(ring.slotCount) slots"
    }
}
