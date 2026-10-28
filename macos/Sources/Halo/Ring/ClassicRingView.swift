import HaloCore
import SwiftUI

/// The Classic theme in the configurator (editor canvas, previews, onboarding): Logitech's
/// Actions Ring. Separate light bubbles on a circle around a small grey hub with ×; the
/// highlighted bubble fills with its tile colour and shows a tooltip.
///
/// The live overlay draws the same ring with Core Animation (`ClassicRingLayerView`) from the
/// same parts (`ClassicBubbleParts`, `ClassicHub`, `ClassicLabel`), so the two look identical.
/// Motion here is the editor's build-in: on first appearance the hub grows, then the bubbles
/// slide out of it clockwise from 12 o'clock.
struct ClassicRingView: View {
    let model: RingViewModel
    let environment: RingEnvironment
    /// Editor build-in: false until the ring has built itself on first appearance.
    @ViewState private var built: Bool

    init(model: RingViewModel, environment: RingEnvironment) {
        self.model = model
        self.environment = environment
        _built = ViewState(initialValue: model.mode != .editor || environment.motion.isInstant)
    }

    /// Bubbles start this far out (× hub radius), under the hub.
    private static let originRadius: CGFloat = 0.6
    /// Bubbles start at this scale.
    private static let startScale: CGFloat = 0.4

    var body: some View {
        let m = model.metrics
        let accent = model.accent.color
        let ring = model.ring
        let geometry = model.geometry
        let motion = environment.motion
        let isEditor = model.mode == .editor
        let reveal: Double = built ? 1 : 0

        ZStack {
            ForEach(0..<ring.slotCount, id: \.self) { i in
                let angle = geometry.centerAngle(of: i)
                ClassicBubble(
                    face: SlotFace(ring.slots[i]),
                    state: model.drawState(ofSlot: i),
                    angle: angle,
                    number: model.slotNumber(i),
                    metrics: m,
                    isEditor: isEditor,
                    accent: accent,
                    environment: environment
                )
                .modifier(PolarTravel(
                    progress: reveal,
                    from: PolarPoint(angle: angle, radius: m.hubRadius * Self.originRadius),
                    to: PolarPoint(angle: angle, radius: m.slotCenterRadius),
                    startScale: Self.startScale,
                    moves: motion.allowsMovement
                ))
                .animation(motion.buildIn(index: i), value: built)
                .modifier(SlotAccessibility(slot: ring.slots[i], index: i, isSelected: model.selected == i, isEnabled: isEditor))
            }

            ClassicHub(
                goesBack: model.hubGoesBack,
                armed: model.isHubArmed,
                holding: model.isHolding,
                badge: model.appBadge,
                metrics: m,
                environment: environment
            )
            .modifier(PolarTravel(progress: reveal, from: .center, to: .center, startScale: 0.5, moves: motion.allowsMovement))
            .animation(motion.buildIn(index: nil), value: built)

            labels(metrics: m)
                .modifier(ProgressFade(progress: reveal, from: 0.7, to: 1))
        }
        .frame(width: m.canvasSide, height: m.canvasSide)
        .onAppear { built = true }
    }

    // MARK: Labels

    /// Tooltip for the focused slot (`.hub`) or a chip on every slot (`.always`).
    @ViewBuilder
    private func labels(metrics m: RingMetrics) -> some View {
        let scale = m.unit
        let motion = environment.motion
        switch model.labelMode {
        case .hub:
            ZStack {
                if let index = model.focusedSlot, model.ring.slots.indices.contains(index), !model.ring.slots[index].isEmpty {
                    let face = SlotFace(model.ring.slots[index])
                    let placement = model.classicLabelPlacement(of: index, style: .tooltip)
                    ClassicLabel(title: face.title, style: .tooltip, placement: placement, scale: scale, environment: environment)
                        .id("\(model.levelID)-\(index)")
                        .transition(.asymmetric(
                            insertion: AnyTransition(TooltipSlide(placement: placement, distance: 4 * scale, moves: motion.allowsMovement))
                                .animation(motion.labelIn),
                            removal: AnyTransition.opacity.animation(motion.labelOut)
                        ))
                }
            }
            .animation(motion.labelIn, value: model.focusedSlot)
        case .always:
            ZStack {
                ForEach(0..<model.ring.slotCount, id: \.self) { i in
                    let slot = model.ring.slots[i]
                    if !slot.isEmpty {
                        ClassicLabel(title: SlotFace(slot).title, style: .chip, placement: model.classicLabelPlacement(of: i, style: .chip),
                                     scale: scale, environment: environment)
                    }
                }
            }
            .id(model.levelID)
            .transition(.opacity.animation(motion.labelOut))
        case .none:
            EmptyView()
        }
    }
}

/// A point around the ring centre (y-down radians).
nonisolated struct PolarPoint: Equatable {
    var angle: Double
    var radius: CGFloat

    static let center = PolarPoint(angle: 0, radius: 0)
}

/// Moves a view that sits at the ring centre from `from` to `to` as `progress` goes 0 → 1,
/// sweeping around the centre (angle and radius interpolate, so it travels along arcs), growing
/// from `startScale` and fading in during the first half. Without movement (Reduce Motion) it
/// stays at `to` and only fades.
struct PolarTravel: ViewModifier, Animatable {
    var progress: Double
    var from: PolarPoint
    var to: PolarPoint
    var startScale: CGFloat
    var moves: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let p = moves ? progress : 1
        let fade = moves ? Progress.smoothstep(0, 0.5, p) : Progress.clamped(progress)
        let angle = Progress.lerp(from.angle, to.angle, p)
        let radius = Progress.lerp(from.radius, to.radius, p)
        content
            .scaleEffect(Progress.lerp(startScale, 1, p))
            .opacity(fade)
            .offset(x: CGFloat(cos(angle)) * radius, y: CGFloat(sin(angle)) * radius)
    }
}

/// Fades content in as `progress` passes from `from` to `to` (labels appearing at the end of the
/// editor's build-in).
struct ProgressFade: ViewModifier, Animatable {
    var progress: Double
    var from: Double
    var to: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.opacity(Progress.smoothstep(from, to, progress))
    }
}

/// The pieces a Classic bubble is drawn from, bottom to top: disc (with its shadow), tile,
/// hairline, ink (glyph, folder arc, adjustable dot), artwork, highlight outline, number badge.
///
/// `ClassicBubble` stacks them in SwiftUI. The live overlay renders each to an image and stacks
/// them as layers, so the render server can animate them independently; both look identical
/// because both draw these.
struct ClassicBubbleParts {
    let face: SlotFace
    /// Direction from the ring centre (y-down radians); the tab and dot face it.
    let angle: Double
    let metrics: RingMetrics
    let environment: RingEnvironment
    /// Folders show their tab unless open.
    var showsTab = true

    var scale: CGFloat { metrics.unit }
    var radius: CGFloat { metrics.slotSize / 2 }
    var shape: BubbleShape { BubbleShape(tabAngle: angle, tabProgress: face.kind == .folder && showsTab ? 1 : 0) }
    /// The highlight colour: the slot's tint or near-black.
    var tile: Color { face.tint?.color ?? ClassicPalette.tile }

    /// The idle disc and its soft shadow (app icons show no disc).
    var disc: some View {
        shape
            .fill(ClassicPalette.bubble.opacity(environment.reduceTransparency ? 1 : 0.9))
            .opacity(face.isAppIcon ? 0 : 1)
            .shadow(color: .black.opacity(environment.colorScheme == .dark ? 0.3 : 0.12), radius: 6 * scale, y: 2 * scale)
    }

    /// The highlighted fill (drawn at the highlight's strength).
    var tileFill: some View { shape.fill(tile) }

    /// The bubble's edge (app icons show it only while highlighted).
    var hairline: some View {
        shape.stroke(.black.opacity(environment.increaseContrast ? 0.45 : 0.08), lineWidth: environment.increaseContrast ? 1 : 0.5)
    }

    /// Everything drawn in the glyph colour, so it can cross-fade between dark and white.
    func ink(_ color: Color, rim: Color) -> some View {
        ZStack {
            if case .symbol = face.icon {
                RingIcon(spec: face.icon, symbolSize: metrics.iconSize * 0.86, appIconSize: metrics.appIconSize, color: color)
            }
            switch face.kind {
            case .folder:
                TabArcGlyph(angle: angle, bubbleRadius: radius)
                    .stroke(color, style: StrokeStyle(lineWidth: 1.4 * scale, lineCap: .round))
                    .opacity(showsTab ? 1 : 0)
            case .adjustable:
                Circle()
                    .fill(color)
                    .overlay { Circle().strokeBorder(rim, lineWidth: 1.2 * scale) }
                    .frame(width: 6.4 * scale, height: 6.4 * scale)
                    .offset(x: CGFloat(cos(angle)) * (radius - 0.5 * scale), y: CGFloat(sin(angle)) * (radius - 0.5 * scale))
            case .empty, .action:
                EmptyView()
            }
        }
    }

    var idleInk: some View { ink(ClassicPalette.glyph, rim: ClassicPalette.bubble) }
    var litInk: some View { ink(.white, rim: tile) }

    /// True when the slot shows artwork in its own colours (app icon, emoji, image).
    var hasArtwork: Bool {
        switch face.icon {
        case .symbol, nil: false
        default: true
        }
    }

    /// App icons, emoji and images keep their own colours.
    @ViewBuilder
    var artwork: some View {
        if hasArtwork {
            RingIcon(spec: face.icon, symbolSize: metrics.iconSize * 0.86, appIconSize: metrics.appIconSize, color: ClassicPalette.glyph)
        }
    }

    /// Increase Contrast / Differentiate Without Colour: an outline on the highlight.
    func highlightOutline(_ accent: Color) -> some View {
        shape.stroke(accent, lineWidth: 2 * scale)
    }

    /// The digit key that runs the slot, on the bubble's inner edge.
    func numberBadge(_ number: Int) -> some View {
        let inward = radius - 1 * scale
        return Text("\(number)")
            .font(.system(size: 8 * scale, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(width: 12 * scale, height: 12 * scale)
            .background(Circle().fill(ClassicPalette.badge))
            .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1 * scale))
            .offset(x: -CGFloat(cos(angle)) * inward, y: -CGFloat(sin(angle)) * inward)
    }

    /// An empty slot: a faint disc with a dashed outline, in the accent while `hot` (hovered or
    /// selected).
    func emptyDisc(hot: Bool, accent: Color) -> some View {
        let stroke = hot ? accent : ClassicPalette.emptyStroke
        return ZStack {
            Circle().fill(hot ? accent.opacity(0.14) : ClassicPalette.bubble.opacity(0.16))
            Circle().strokeBorder(stroke.opacity(environment.increaseContrast ? 1 : 0.85),
                                  style: StrokeStyle(lineWidth: 1.5 * scale, dash: [3.2 * scale, 3 * scale]))
        }
    }

    /// An empty slot's rejection flash at full strength (`RejectFlash`'s look).
    var rejectFlash: some View {
        Circle().fill(Color.red.opacity(0.22))
            .overlay { Circle().stroke(Color.red.opacity(0.85), lineWidth: 1.5) }
    }
}

/// One Classic bubble in the configurator: idle light disc with a dark glyph; highlighted, its
/// tile colour with a white glyph. Draws the folder tab, adjustable dot, slot number and the
/// editor's selection, drop-target, drag and inherited states.
struct ClassicBubble: View {
    let face: SlotFace
    let state: SlotDrawState
    /// Direction from the ring centre (y-down radians); the tab and dot face it.
    let angle: Double
    let number: Int?
    let metrics: RingMetrics
    let isEditor: Bool
    let accent: Color
    let environment: RingEnvironment

    private var scale: CGFloat { metrics.unit }
    private var parts: ClassicBubbleParts {
        ClassicBubbleParts(face: face, angle: angle, metrics: metrics, environment: environment, showsTab: !state.isOpenFolder)
    }

    var body: some View {
        let d = metrics.slotSize
        let motion = environment.motion
        ZStack {
            if state.isDropTarget {
                Circle()
                    .fill(accent.opacity(0.55))
                    .frame(width: d + 10 * scale, height: d + 10 * scale)
                    .blur(radius: 7 * scale)
            }
            if face.isEmpty { emptyBody } else { filledBody }
        }
        .frame(width: d, height: d)
        .overlay { if let number { parts.numberBadge(number) } }
        .overlay { inheritedOutline }
        .scaleEffect(liftScale)
        // Fades apply to the flattened bubble, so its shadow never shows through its fill.
        .compositingGroup()
        .opacity(state.opacity)
        .animation(motion.classicHighlight, value: state.highlight)
        .animation(motion.emphasis, value: state.isSelected)
        .animation(motion.emphasis, value: state.isDropTarget)
        .animation(motion.emphasis, value: state.isDragSource)
        .animation(motion.contentSwap, value: face)
    }

    /// Drop target 1.08, dragged slot 1.06, selection 1.03 (SPEC "subtle lift").
    private var liftScale: CGFloat {
        if state.isDropTarget { return 1.08 }
        if state.isDragSource { return 1.06 }
        return state.isSelected ? 1.03 : 1
    }

    /// An inherited slot (app ring showing the Everywhere ring's action): a dashed ring.
    @ViewBuilder
    private var inheritedOutline: some View {
        if state.isInherited && !face.isEmpty {
            Circle()
                .strokeBorder(ClassicPalette.emptyStroke, style: StrokeStyle(lineWidth: 1.5 * scale, dash: [3.2 * scale, 3 * scale]))
                .padding(-3 * scale)
        }
    }

    private var filledBody: some View {
        let parts = parts
        let shape = parts.shape
        let h = state.highlight
        let lifted = state.isSelected || state.isDropTarget || state.isDragSource
        return ZStack {
            if isEditor {
                // The deeper shadow of a lifted bubble: pre-blurred, only its opacity animates.
                shape
                    .fill(Color.black)
                    .blur(radius: 6 * scale)
                    .offset(y: 3 * scale)
                    .opacity(lifted ? 0.2 : 0)
            }
            parts.disc
            parts.tileFill.opacity(h)
            parts.hairline.opacity(face.isAppIcon ? h : 1)
            InkBlend(highlight: h, idle: parts.idleInk, lit: parts.litInk)
            parts.artwork
            if environment.outlinesHighlight {
                parts.highlightOutline(accent).opacity(h)
            }
            if state.isSelected || state.isDropTarget {
                shape
                    .stroke(accent, lineWidth: 2.5 * scale)
                    .padding(-3.5 * scale)
            }
        }
    }

    /// A faint dashed circle with a "+" (accent when hovered, selected or a drop target).
    private var emptyBody: some View {
        let hot = state.highlight > 0 || state.isSelected || state.isDropTarget
        return ZStack {
            parts.emptyDisc(hot: hot, accent: accent)
            if isEditor {
                Image(systemName: "plus")
                    .font(.system(size: metrics.iconSize * 0.7, weight: .medium))
                    .foregroundStyle(hot ? accent : ClassicPalette.emptyStroke)
            }
            if state.isSelected || state.isDropTarget {
                Circle()
                    .strokeBorder(accent, lineWidth: 2.5 * scale)
                    .padding(-3.5 * scale)
            }
        }
    }
}

/// The Classic hub: a small grey disc with a white × (close) or chevron (back). Over the hub in
/// tap mode it turns pale red with a red ×. App rings show the app's icon as a badge.
struct ClassicHub: View {
    let goesBack: Bool
    let armed: Bool
    let holding: Bool
    let badge: RingViewModel.AppBadge?
    let metrics: RingMetrics
    let environment: RingEnvironment

    var body: some View {
        let scale = metrics.unit
        let d = metrics.hubRadius * 2
        let red = armed && !goesBack
        let fill: Color = red
            ? Color(nsColor: .systemRed).opacity(environment.reduceTransparency ? 0.45 : 0.3)
            : ClassicPalette.hub.opacity(environment.reduceTransparency || environment.increaseContrast ? 0.85 : (armed ? 0.75 : 0.55))
        ZStack {
            Circle()
                .fill(fill)
                .shadow(color: .black.opacity(0.1), radius: 4 * scale, y: 1 * scale)
            Circle().strokeBorder(.black.opacity(environment.increaseContrast ? 0.4 : 0.07), lineWidth: 0.5)
            Image(systemName: goesBack ? "chevron.backward" : "xmark")
                .font(.system(size: metrics.hubIconSize * (goesBack ? 0.9 : 0.8), weight: .bold))
                .foregroundStyle(red ? Color(nsColor: .systemRed) : .white)
                .opacity(holding ? 0.6 : 1)
                .offset(x: goesBack ? -0.7 * scale : 0)
        }
        .frame(width: d, height: d)
        .overlay(alignment: .bottomTrailing) {
            if let badge {
                Image(nsImage: AppCatalog.shared.icon(forBundleID: badge.bundleID))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 14 * scale, height: 14 * scale)
                    .shadow(color: .black.opacity(0.25), radius: 1.5 * scale, y: 0.5 * scale)
                    .offset(x: 5 * scale, y: 5 * scale)
            }
        }
        .animation(environment.motion.classicHighlight, value: armed)
        .animation(environment.motion.dim, value: goesBack)
        .accessibilityHidden(true)
    }
}

/// Exposes a slot to VoiceOver in the editor (the editor's own layer handles the clicks).
struct SlotAccessibility: ViewModifier {
    let slot: Slot
    let index: Int
    let isSelected: Bool
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(slot.isEmpty ? "Empty slot" : slot.displayTitle)
                .accessibilityValue("Slot \(index + 1)")
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        } else {
            content.accessibilityHidden(true)
        }
    }
}
