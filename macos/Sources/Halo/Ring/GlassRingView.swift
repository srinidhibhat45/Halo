import HaloCore
import SwiftUI

/// The Glass theme: one `GlassEffectContainer` holding a segmented annulus of Liquid Glass
/// sectors around a glass hub that names the highlighted slot. Folders fan out as a partial
/// outer band; the root ring dims behind it.
///
/// Liquid Glass ignores opacity on a glass view and draws a scaled glass view's content out of
/// register with its glass, so nothing here scales or fades glass. Every motion is a change of
/// geometry: the segments and the hub are `Animatable` views that rebuild their glass shape from
/// the animated progress on every frame and place their glyphs from the same numbers, so glass
/// and content cannot drift apart. On appear the hub grows from a point while the segments
/// extrude out of it one after another, clockwise from 12 o'clock (`RingMotion.bloomDelay`;
/// overlapping glass in the container merges, so it reads as liquid flowing outward); folder
/// children extrude from their folder's outer edge and spread along the arc. Each segment runs
/// its own delayed spring, so only the segments still growing are re-rendered on a frame.
struct GlassRingView: View {
    let model: RingViewModel
    let environment: RingEnvironment
    let stage: RingStage
    /// Editor build-in: false until the ring has built itself on first appearance.
    @ViewState private var built: Bool
    @Environment(\.ringMotionFreeze) private var freeze

    init(model: RingViewModel, environment: RingEnvironment, stage: RingStage) {
        self.model = model
        self.environment = environment
        self.stage = stage
        _built = ViewState(initialValue: model.mode != .editor || environment.motion.isInstant)
    }

    var body: some View {
        let m = model.metrics
        let base = model.baseRing
        let geometry = RingGeometry(slotCount: base.slotCount)
        let fanned = model.isFanned
        let motion = environment.motion
        let isEditor = model.mode == .editor
        // Reduce Motion: the live ring stays in shape and the whole container cross-fades (glass
        // honours opacity on its container, not on itself).
        let fadesWhole = model.mode == .live && !motion.allowsMovement
        let reveal = isEditor ? (built ? 1 : 0) : (fadesWhole ? 1 : stage.appear)
        // Segments animate to their own target with their own (delayed) spring; the hub follows
        // the stage's appear progress.
        let shown: Double = isEditor ? (built ? 1 : 0) : (fadesWhole || model.mode != .live || model.isPresented ? 1 : 0)

        GlassEffectContainer(spacing: m.segmentGap / 2) {
            ZStack {
                ForEach(0..<base.slotCount, id: \.self) { i in
                    let sector = geometry.sector(of: i)
                    let state = freeze.applied(to: fanned ? model.drawState(ofRootSlot: i) : model.drawState(ofSlot: i))
                    // Choosing a slot folds the rest of the ring into the hub while it pulses.
                    let folds = model.executing != nil && (fanned || model.executing != i)
                    let lift = GlassSegment.editorLift(state)
                    ExecutePulse(isExecuting: !fanned && state.isExecuting, motion: motion) { pulse in
                        GlassSegment(
                            face: SlotFace(base.slots[i]),
                            state: state,
                            rest: SectorGeometry(midAngle: (sector.start + sector.end) / 2, span: sector.end - sector.start,
                                                 innerRadius: m.innerRadius, outerRadius: m.outerRadius,
                                                 gap: m.segmentGap, cornerRadius: 8 * m.unit),
                            origin: .hub(radius: m.hubRadius),
                            revealDelay: 0,
                            number: fanned ? nil : model.slotNumber(i),
                            labelMode: fanned ? .none : model.labelMode,
                            isEditor: isEditor,
                            metrics: m,
                            accent: model.accent.color,
                            environment: environment,
                            reveal: folds ? 0 : shown,
                            highlight: state.highlight,
                            lift: lift,
                            pulse: pulse
                        )
                    }
                    .animation(motion.glassHighlight, value: state.highlight)
                    .animation(motion.emphasis, value: lift)
                    .animation(motion.dim, value: state.isDimmed)
                    .animation(model.isPresented
                               ? motion.glassSegmentAppear(index: i, count: base.slotCount, staggered: stage.staggersAppear)
                               : motion.dismiss,
                               value: model.isPresented)
                    .animation(motion.dismiss, value: folds)
                    .animation(motion.buildIn(index: i), value: built)
                    .modifier(SlotAccessibility(slot: base.slots[i], index: i, isSelected: model.selected == i, isEnabled: isEditor && !fanned))
                }

                ForEach(stage.fans) { layer in
                    GlassFanLayer(model: model, layer: layer, environment: environment)
                        .onAppear { stage.unfold(layer.id) }
                }

                GlassHub(
                    title: hubTitle,
                    goesBack: model.hubGoesBack,
                    folderName: model.breadcrumb.last,
                    badge: model.appBadge,
                    armed: model.isHubArmed,
                    showsHint: !isEditor,
                    metrics: m,
                    environment: environment,
                    reveal: reveal
                )
                .animation(motion.buildIn(index: nil), value: built)
            }
            .frame(width: m.canvasSide, height: m.canvasSide)
        }
        .opacity(fadesWhole ? Progress.clamped(stage.appear) : 1)
        .frame(width: m.canvasSide, height: m.canvasSide)
        .onAppear { built = true }
    }

    /// The focused slot's title for the hub, unless labels are off or the slot is empty.
    private var hubTitle: String? {
        guard model.labelMode != .none, let index = model.focusedSlot, model.ring.slots.indices.contains(index) else { return nil }
        let slot = model.ring.slots[index]
        return slot.isEmpty ? nil : slot.displayTitle
    }
}

/// A folder's children as a partial glass band beyond the ring. They extrude from the folder's
/// outer edge (or, for a nested folder, from its place on the arc) and spread along the arc to
/// their slots, the centre child first; folding reverses it.
private struct GlassFanLayer: View {
    let model: RingViewModel
    let layer: FanLayer
    let environment: RingEnvironment
    @Environment(\.ringMotionFreeze) private var freeze

    var body: some View {
        let m = model.metrics
        let motion = environment.motion
        let count = layer.ring.slotCount
        // The open layer's children are the model's current level; folding layers are inert.
        let isCurrent = layer.isOpen
        let origin = SegmentOrigin.point(
            angle: layer.sourceAngle,
            radius: layer.sourceIsRootSlot ? m.outerRadius : m.folderRadius
        )
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                let state = isCurrent ? freeze.applied(to: model.drawState(ofSlot: i)) : SlotDrawState()
                let folds = isCurrent && model.executing != nil && model.executing != i
                ExecutePulse(isExecuting: state.isExecuting, motion: motion) { pulse in
                    GlassSegment(
                        face: SlotFace(layer.ring.slots[i]),
                        state: state,
                        rest: SectorGeometry(midAngle: layer.arc.angle(of: i), span: layer.arc.step,
                                             innerRadius: m.folderRadius - m.slotSize / 2, outerRadius: m.folderRadius + m.slotSize / 2,
                                             gap: m.segmentGap, cornerRadius: 8 * m.unit),
                        origin: origin,
                        revealDelay: Progress.fanDelay(index: i, count: count),
                        number: isCurrent ? model.slotNumber(i) : nil,
                        labelMode: model.labelMode,
                        isEditor: false,
                        metrics: m,
                        accent: model.accent.color,
                        environment: environment,
                        reveal: folds ? 0 : layer.progress,
                        highlight: state.highlight,
                        lift: 0,
                        pulse: pulse
                    )
                }
                .animation(motion.glassHighlight, value: state.highlight)
                .animation(motion.dismiss, value: folds)
            }
        }
    }
}

/// Where a glass segment grows from.
enum SegmentOrigin: Equatable {
    /// Out of the hub, from inside its edge as the hub itself grows (appear).
    case hub(radius: CGFloat)
    /// Out of a point `radius` from the centre in direction `angle` (a folder's edge).
    case point(angle: Double, radius: CGFloat)
}

/// One glass sector with its icon (and optional caption, number, folder arc or adjustable dot).
/// Highlighted: tinted with the slot's tint or the accent, white glyph, grown outward, bounce.
///
/// Animatable: `reveal`, `highlight` and `lift` are interpolated by SwiftUI and the sector's
/// geometry is recomputed from them on every frame, for the glass shape and the content alike.
struct GlassSegment: View, Animatable {
    let face: SlotFace
    let state: SlotDrawState
    /// The sector when fully shown.
    let rest: SectorGeometry
    let origin: SegmentOrigin
    /// Progress units by which this segment starts after `reveal` does.
    let revealDelay: Double
    let number: Int?
    let labelMode: LabelMode
    let isEditor: Bool
    let metrics: RingMetrics
    let accent: Color
    let environment: RingEnvironment
    /// Appear or fan progress: 0 not yet grown out of `origin` … 1 at `rest`.
    var reveal: Double
    /// Highlight strength (0 … 1).
    var highlight: Double
    /// Editor lift (selection, drop target, drag), as a fraction of the band's thickness.
    var lift: CGFloat
    /// Execute pulse (0 … 1 … 0): grows the segment outward and brightens its tint.
    var pulse: Double

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, CGFloat>> {
        get { AnimatablePair(reveal, AnimatablePair(highlight, lift)) }
        set {
            reveal = newValue.first
            highlight = newValue.second.first
            lift = newValue.second.second
        }
    }

    /// Bumped each time the slot becomes highlighted, to bounce its symbol.
    @ViewState private var bounces = 0

    /// Strength of the glass tint on a highlighted segment (SPEC: 0.45).
    static let glassTintOpacity = 0.45
    /// A highlighted segment also carries a colour layer in its content, so the white glyph stays
    /// legible over bright backdrops (and the highlight shows where glass tint doesn't render).
    static let fillOpacity = 0.62

    /// The editor's lift for `state`: drop target 0.08, dragged 0.06, selected 0.02 of the band
    /// (the SPEC's 1.08 / 1.06 / 1.02 scales, as a shape change).
    static func editorLift(_ state: SlotDrawState) -> CGFloat {
        state.isDropTarget ? 0.08 : state.isDragSource ? 0.06 : state.isSelected ? 0.02 : 0
    }

    private var scale: CGFloat { metrics.unit }
    private var moves: Bool { environment.motion.allowsMovement }
    /// Progress of this segment's own growth, after its delay.
    private var growth: Double { moves ? Progress.delayed(reveal, by: revealDelay) : 1 }

    /// The sector on this frame: grown out of its origin, then lifted.
    private var current: SectorGeometry {
        let s = growth
        let emerged: SectorGeometry
        switch origin {
        case .hub(let radius):
            let start = radius * 0.55 * CGFloat(GlassHub.growth(reveal))
            emerged = rest.emerging(fromAngle: rest.midAngle, radius: start, progress: s)
        case .point(let angle, let radius):
            emerged = rest.emerging(fromAngle: angle, radius: radius, progress: s)
        }
        let amount = max(lift, 0.05 * CGFloat(highlight)) + 0.08 * CGFloat(pulse)
        return emerged.lifted(by: amount)
    }

    var body: some View {
        let side = metrics.canvasSide
        let g = current
        let shape = g.shape
        let motion = environment.motion
        // Glass ignores opacity on its own view, so dimmed, inherited and dragged segments fade
        // their content and use the lighter `.clear` glass instead.
        let rt = environment.reduceTransparency
        content(g, shape: shape)
            .opacity(rt ? 1 : state.opacity)
            .frame(width: side, height: side)
            .background { solidBackground(shape) }
            .glassEffect(glass, in: shape)
            .overlay { outlines(shape) }
            .opacity(rt ? state.opacity : 1)
            .modifier(RejectFlash(token: state.rejectToken, shape: shape, motion: motion))
            .animation(motion.emphasis, value: state.isSelected)
            .animation(motion.emphasis, value: state.isDropTarget)
            .animation(motion.contentSwap, value: face)
            .onChange(of: state.highlight) { old, new in
                if new >= 1, old < 1 { bounces += 1 }
            }
    }

    private var tint: Color { face.tint?.color ?? accent }

    private var glass: Glass {
        guard !environment.reduceTransparency else { return .identity }
        if highlight > 0.001 { return Glass.regular.tint(tint.opacity(Self.glassTintOpacity * highlight)).interactive() }
        let recessive = state.isDimmed || state.isInherited || (face.isEmpty && !isEditor)
        return (recessive ? Glass.clear : .regular).interactive()
    }

    // MARK: Content

    private func content(_ g: SectorGeometry, shape: AnnularSector) -> some View {
        let h = highlight
        let white = InkBlend<EmptyView, EmptyView>.litStrength(h)
        let s = growth
        // Glyphs ride on the growth: they fade in over its middle and settle from 0.7 scale.
        let shown = moves ? Progress.smoothstep(0.35, 0.85, s) : Progress.clamped(reveal)
        let glyphScale = moves ? Progress.lerp(0.7, 1, Progress.clamped(s)) : 1
        let center = g.point(atRadius: g.midRadius)
        let showsCaption = labelMode == .always && !face.isEmpty
        // Sized from the resting sector so the caption never re-lays out while animating.
        let chord = 2 * rest.midRadius * CGFloat(sin(rest.span / 2)) - 14 * scale
        // Captions go on the outer side vertically (above the icon in the top half, else below),
        // numbers on the inner side, so neither collides.
        let captionAbove = sin(rest.midAngle) < -0.3
        let iconShift: CGFloat = showsCaption ? (captionAbove ? 8 : -8) * scale : 0
        let captionShift: CGFloat = (captionAbove ? -12 : 12) * scale
        return ZStack {
            if !environment.reduceTransparency {
                shape.fill(tint.opacity(min(1, Self.fillOpacity * h + 0.18 * pulse)))
            }
            InkBlend(highlight: h, idle: glyph(color: .primary), lit: glyph(color: .white))
            .symbolEffect(.bounce.up.byLayer, value: bounces)
            .scaleEffect(glyphScale)
            .offset(y: iconShift)
            .opacity(shown)
            .offset(x: center.x, y: center.y)

            if showsCaption {
                Text(face.title)
                    .font(.system(size: metrics.labelFontSize, weight: .medium))
                    .foregroundStyle(h >= 0.5 ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: max(chord, 20 * scale))
                    .offset(y: captionShift)
                    .opacity(shown)
                    .offset(x: center.x, y: center.y)
            }

            if let number {
                let p = g.point(atRadius: g.innerRadius + 9 * scale)
                Text("\(number)")
                    .font(.system(size: 9 * scale, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(h >= 0.5 ? AnyShapeStyle(Color.white.opacity(0.85)) : AnyShapeStyle(.tertiary))
                    .opacity(shown)
                    .offset(x: p.x, y: p.y)
            }
            marker(g, white: white)
                .opacity(shown)
        }
        .symbolEffectsRemoved(!moves)
    }

    @ViewBuilder
    private func glyph(color: Color) -> some View {
        if face.isEmpty {
            if isEditor {
                Image(systemName: "plus")
                    .font(.system(size: metrics.iconSize * 0.7, weight: .medium))
                    .foregroundStyle(state.highlight > 0 || state.isSelected ? accent : color.opacity(0.45))
            }
        } else {
            RingIcon(spec: face.icon, symbolSize: metrics.iconSize * 0.84, appIconSize: metrics.appIconSize,
                     color: color, renderingMode: .hierarchical)
        }
    }

    /// Folder: a short arc along the outer edge (Logitech's arc glyph). Adjustable: a dot.
    @ViewBuilder
    private func marker(_ g: SectorGeometry, white: Double) -> some View {
        let r = g.outerRadius - 7 * scale
        let color = Color.primary.opacity(0.45).mix(with: .white, by: white)
        switch face.kind {
        case .folder where !state.isOpenFolder:
            let halfSpan = min(Double(11 * scale / max(r, 1)), g.span * 0.18)
            RingArc(angle: g.midAngle, halfSpan: halfSpan, radius: r)
                .stroke(color, style: StrokeStyle(lineWidth: 2 * scale, lineCap: .round))
        case .adjustable:
            let p = g.point(atRadius: r)
            Circle()
                .fill(color)
                .frame(width: 5.5 * scale, height: 5.5 * scale)
                .offset(x: p.x, y: p.y)
        default:
            EmptyView()
        }
    }

    // MARK: Reduce Transparency and outlines

    @ViewBuilder
    private func solidBackground(_ shape: AnnularSector) -> some View {
        if environment.reduceTransparency {
            ZStack {
                shape
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: .black.opacity(0.18), radius: 6 * scale, y: 2 * scale)
                shape.fill(tint).opacity(highlight)
                shape.stroke(Color.primary.opacity(0.16), lineWidth: 0.5)
            }
        }
    }

    @ViewBuilder
    private func outlines(_ shape: AnnularSector) -> some View {
        ZStack {
            if environment.increaseContrast {
                shape.stroke(Color.primary.opacity(0.55), lineWidth: 1)
            }
            if environment.outlinesHighlight {
                shape.stroke(Color.primary, lineWidth: 2 * scale).opacity(highlight)
            }
            if state.isDropTarget {
                shape.stroke(accent, lineWidth: 4 * scale).blur(radius: 5 * scale)
            }
            if state.isSelected || state.isDropTarget {
                shape.stroke(accent, lineWidth: 2.5 * scale)
            }
            if state.isInherited && !face.isEmpty {
                shape.stroke(Color.primary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5 * scale, dash: [3.5 * scale, 3 * scale]))
            }
        }
    }
}

/// The glass hub: the focused slot's title, or a hint (×/Close, the app's icon, or a back
/// chevron with the folder's name). Tinted red while the pointer is over it in tap mode.
///
/// Animatable: on appear it grows from a point (its glass disc's radius follows `reveal` every
/// frame) a little ahead of the segments, and its label grows and fades in with it.
struct GlassHub: View, Animatable {
    let title: String?
    let goesBack: Bool
    let folderName: String?
    let badge: RingViewModel.AppBadge?
    let armed: Bool
    /// Live and preview rings show the close/back hint when nothing is focused.
    let showsHint: Bool
    let metrics: RingMetrics
    let environment: RingEnvironment
    /// Appear progress (0 … 1).
    var reveal: Double

    var animatableData: Double {
        get { reveal }
        set { reveal = newValue }
    }

    /// The hub's size (0 … 1) at appear progress `reveal`: it leads the segments, reaching full
    /// size at 0.8 with an ease-out, and is gone just before the ring finishes collapsing.
    static func growth(_ reveal: Double) -> Double {
        let t = Progress.clamped((reveal - 0.02) / 0.78)
        return 1 - (1 - t) * (1 - t)
    }

    var body: some View {
        let d = metrics.hubRadius * 2
        let scale = metrics.unit
        let moves = environment.motion.allowsMovement
        let grown = moves ? Self.growth(reveal) : 1
        let disc = HubDisc(radius: metrics.hubRadius * CGFloat(grown))
        let shown = moves ? Progress.smoothstep(0.5, 0.9, grown) : Progress.clamped(reveal)
        let red = armed && !goesBack && title == nil
        ZStack {
            if !environment.reduceTransparency {
                disc.fill(Color(nsColor: .systemRed).opacity(red ? 0.24 : 0))
            }
            label(diameter: d, scale: scale)
                .id(labelKey)
                .transition(environment.motion.allowsMovement ? AnyTransition(.blurReplace) : .opacity)
                // Shrinks with the disc so it never spills out of it (content, not glass).
                .scaleEffect(moves ? max(CGFloat(grown), 0.3) : 1)
                .opacity(shown)
        }
        .frame(width: d, height: d)
        .background {
            if environment.reduceTransparency {
                disc
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay { disc.fill(Color(nsColor: .systemRed).opacity(red ? 0.22 : 0)) }
                    .overlay { disc.stroke(Color.primary.opacity(0.16), lineWidth: 0.5) }
                    .shadow(color: .black.opacity(0.18), radius: 6 * scale, y: 2 * scale)
            }
        }
        .glassEffect(glass(red: red), in: disc)
        .overlay {
            if environment.increaseContrast { disc.stroke(Color.primary.opacity(0.55), lineWidth: 1) }
        }
        .animation(environment.motion.glassHighlight, value: labelKey)
        .animation(environment.motion.glassHighlight, value: red)
        .accessibilityHidden(true)
    }

    private func glass(red: Bool) -> Glass {
        guard !environment.reduceTransparency else { return .identity }
        return (red ? Glass.regular.tint(Color(nsColor: .systemRed).opacity(0.35)) : .regular).interactive()
    }

    /// Identity of what the hub shows, so changes blur-replace.
    private var labelKey: String {
        if let title { return "title:" + title }
        return goesBack ? "back:" + (folderName ?? "") : "hint"
    }

    @ViewBuilder
    private func label(diameter d: CGFloat, scale: CGFloat) -> some View {
        if let title {
            Text(title)
                .font(.system(size: metrics.hubLabelFontSize, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .foregroundStyle(.primary)
                .frame(width: d * 0.74)
        } else if goesBack || showsHint {
            VStack(spacing: 4 * scale) {
                if let badge, !goesBack {
                    Image(nsImage: AppCatalog.shared.icon(forBundleID: badge.bundleID))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 26 * scale, height: 26 * scale)
                } else {
                    Image(systemName: goesBack ? "chevron.backward" : "xmark")
                        .font(.system(size: metrics.hubIconSize * 0.62, weight: .semibold))
                        .foregroundStyle(armed && !goesBack ? Color(nsColor: .systemRed) : Color.primary.opacity(0.75))
                }
                Text(goesBack ? (folderName ?? "Back") : "Close")
                    .font(.system(size: 10.5 * scale, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: d * 0.7)
            }
        } else if let badge {
            Image(nsImage: AppCatalog.shared.icon(forBundleID: badge.bundleID))
                .resizable()
                .interpolation(.high)
                .frame(width: 30 * scale, height: 30 * scale)
        }
    }
}
