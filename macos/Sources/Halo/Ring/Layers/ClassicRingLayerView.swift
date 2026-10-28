import AppKit
import HaloCore
import Observation
import SwiftUI

/// The live overlay's Classic ring, drawn with Core Animation so its motion runs on the render
/// server at the display's full rate (120 Hz on ProMotion), whatever the main thread is doing.
///
/// It observes `model` (`withObservationTracking`, re-armed after every change) and, in its next
/// layout pass, turns what changed into animations: the one-after-another bloom and the
/// collapse, highlights and tooltips, folder fans and root dimming, the execute pulse and the
/// reject shake (`ClassicLayerMotion`). Nothing runs per frame on the main thread: each change
/// commits keyframe tracks once (`LayerAnimation`). Every animated value is an analytic
/// `Trajectory`, so an interruption (reopening mid-dismiss, switching folders mid-fan, sweeping
/// the highlight) starts the next motion from the value's current position and velocity.
/// Input never waits for it: the overlay hit-tests the model, not the layers.
///
/// Its images come from the same SwiftUI parts as `ClassicRingView` (`ClassicArtwork`), made
/// when a ring is set up (before it is shown), cached, and reused across openings; the layers
/// themselves are reused too. The ring is centred in the view, y down, like the SwiftUI ring.
final class ClassicRingLayerView: NSView {
    /// What the ring's look depends on beyond the model.
    struct Appearance: Equatable {
        var dark: Bool
        var reduceTransparency: Bool
        var increaseContrast: Bool
        var differentiateWithoutColor: Bool
        var reduceMotion: Bool
        /// Device pixels per point.
        var pixelScale: CGFloat
    }

    let model: RingViewModel
    /// A fixed appearance instead of the window's and the system's (the snapshot renderer).
    var pinnedAppearance: Appearance? {
        didSet { needsLayout = true }
    }

    /// The ring's clock: every animation is timed in this layer's time, so freezing it
    /// (`speed = 0`, `timeOffset = t`) holds the whole ring at moment `t`.
    let clock = CALayer()
    /// Carries the reject shake for everything below it.
    private let shaker = CALayer()
    private let rootLayer = CALayer()
    private let fanLayer = CALayer()
    private let labelLayer = CALayer()
    private let hub = ClassicHubNode()
    private var roots: [ClassicBubbleNode] = []
    private var fans: [Fan] = []
    private var applied: Applied?
    /// An observation of the model is armed (one at a time, re-armed after it fires).
    private var isObserving = false
    /// The ring centre relative to the containers' origin (the centre snapped to device pixels).
    private var centreOffset = CGPoint.zero
    private var cleanup: Task<Void, Never>?
    private var prewarm: Task<Void, Never>?
    private var accessibilityObserver: NSObjectProtocol?

    /// A folder's children fanned out on the outer arc (open), or folding back into it.
    private final class Fan {
        let id: [Int]
        var ring: Ring
        var nodes: [ClassicBubbleNode] = []
        var isOpen = true

        init(id: [Int], ring: Ring) {
            self.id = id
            self.ring = ring
        }
    }

    /// What the last sync showed, to tell what changed.
    private struct Applied {
        var levelID: Int
        var executing: Int?
        var rejectCount: Int
        var style: ClassicArtStyle
    }

    init(model: RingViewModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        for container in [clock, shaker, rootLayer, fanLayer, labelLayer] {
            container.anchorPoint = .zero
            container.bounds = .zero
        }
        layer?.addSublayer(clock)
        clock.addSublayer(shaker)
        // Folder children slide out from under their folder bubble (they never overlap the root
        // ring once fanned out); labels go above everything.
        shaker.addSublayer(fanLayer)
        shaker.addSublayer(rootLayer)
        shaker.addSublayer(hub.layer)
        shaker.addSublayer(labelLayer)
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.needsLayout = true }
        }
        needsLayout = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    isolated deinit {
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
        cleanup?.cancel()
        prewarm?.cancel()
    }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {}
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        sync()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    // MARK: Accessibility (the live ring is one element naming the highlight)

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { "Action ring" }
    override func accessibilityValue() -> Any? {
        guard let index = model.highlighted, model.ring.slots.indices.contains(index) else { return "" }
        return model.ring.slots[index].displayTitle
    }

    // MARK: Sync

    /// Now on the ring's clock.
    private var now: Double { clock.convertTime(CACurrentMediaTime(), from: nil) }

    private var ringAppearance: Appearance {
        if let pinnedAppearance { return pinnedAppearance }
        let workspace = NSWorkspace.shared
        return Appearance(
            dark: effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua,
            reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast,
            differentiateWithoutColor: workspace.accessibilityDisplayShouldDifferentiateWithoutColor,
            reduceMotion: workspace.accessibilityDisplayShouldReduceMotion,
            pixelScale: window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        )
    }

    /// Brings the layers in line with the model, turning each change into animations, and
    /// re-arms observation. Runs in layout; the snapshot renderer also calls it directly.
    func sync() {
        let state: State
        if isObserving {
            state = State(model)
        } else {
            isObserving = true
            state = withObservationTracking { State(model) } onChange: { [weak self] in
                MainActor.assumeIsolated {
                    self?.isObserving = false
                    self?.needsLayout = true
                }
            }
        }
        let appearance = ringAppearance
        let m = state.metrics
        let motion = ClassicLayerMotion(speed: state.speed, reduceMotion: appearance.reduceMotion)
        let style = ClassicArtStyle(unit: m.unit, pixelScale: appearance.pixelScale, dark: appearance.dark,
                                    reduceTransparency: appearance.reduceTransparency, increaseContrast: appearance.increaseContrast,
                                    differentiateWithoutColor: appearance.differentiateWithoutColor, accent: state.accent)
        let now = now
        let newRing = state.levelID != applied?.levelID && state.isNewRing
        LayerAnimation.withoutActions {
            placeContainers(style)
            syncRoots(state, style: style, motion: motion, now: now)
            syncFans(state, style: style, motion: motion, now: now, newRing: newRing)
            syncHub(state, style: style, motion: motion, now: now)
            if let applied, state.rejectCount != applied.rejectCount, let index = state.rejected {
                (state.isFanned ? fans.last(where: \.isOpen)?.nodes : roots)?.element(at: index)?.flashRejection(now: now, motion: motion)
                shake(now: now, motion: motion, unit: m.unit)
            }
        }
        if newRing || applied?.style != style { prewarmFolders(of: state.baseRing, style: style, metrics: m) }
        applied = Applied(levelID: state.levelID, executing: state.executing, rejectCount: state.rejectCount, style: style)
    }

    /// The model as last read (inside observation tracking).
    private struct State {
        var presented: Bool
        var levelID: Int
        /// The level was replaced from scratch (a new session), not entered or left.
        var isNewRing: Bool
        var baseRing: Ring
        var isFanned: Bool
        var anchor: Int?
        var fan: FanLayer?
        var highlighted: Int?
        var executing: Int?
        var rejected: Int?
        var rejectCount: Int
        var hub: ClassicHubFace
        var labelMode: LabelMode
        var accent: RingColor
        var speed: Double
        var metrics: RingMetrics
        var rootNumbers: [Int?]
        var levelNumbers: [Int?]
        var levelFaces: [SlotFace]

        init(_ model: RingViewModel) {
            presented = model.isPresented
            levelID = model.levelID
            isNewRing = model.levelTransition == .none
            baseRing = model.baseRing
            isFanned = model.isFanned
            anchor = model.folderAnchor
            fan = model.currentFan
            highlighted = model.highlighted
            executing = model.executing
            rejected = model.rejected
            rejectCount = model.rejectCount
            hub = ClassicHubFace(goesBack: model.hubGoesBack, armed: model.isHubArmed, holding: model.isHolding,
                                 badgeBundleID: model.appBadge?.bundleID)
            labelMode = model.labelMode
            accent = model.accent
            speed = model.animationSpeed
            metrics = model.metrics
            rootNumbers = (0..<baseRing.slotCount).map { model.isFanned ? nil : model.slotNumber($0) }
            levelNumbers = (0..<model.ring.slotCount).map(model.slotNumber)
            levelFaces = model.ring.slots.map(SlotFace.init)
        }
    }

    /// Centres the ring in the view; the containers' origin is the centre on whole pixels.
    private func placeContainers(_ style: ClassicArtStyle) {
        clock.frame = bounds
        let middle = CGPoint(x: bounds.midX, y: bounds.midY)
        let snapped = style.snapped(middle)
        centreOffset = CGPoint(x: middle.x - snapped.x, y: middle.y - snapped.y)
        shaker.position = snapped
    }

    /// Where a bubble `offset` from the ring centre rests: on whole device pixels, where SwiftUI
    /// would round it (so images are never resampled at rest).
    private func placement(angle: Double, offset: CGPoint, origin: PolarPoint, startScale: CGFloat, labelFadeFrom: Double,
                           style: ClassicArtStyle) -> ClassicBubbleNode.Placement {
        let rest = style.snapped(CGPoint(x: centreOffset.x + offset.x, y: centreOffset.y + offset.y))
        return ClassicBubbleNode.Placement(angle: angle, rest: rest, origin: origin, startScale: startScale, labelFadeFrom: labelFadeFrom)
    }

    // MARK: Root ring

    private func syncRoots(_ state: State, style: ClassicArtStyle, motion: ClassicLayerMotion, now: Double) {
        let base = state.baseRing
        let count = base.slotCount
        let m = state.metrics
        while roots.count > count { roots.removeLast().removeFromRing() }
        while roots.count < count {
            let node = ClassicBubbleNode()
            rootLayer.addSublayer(node.travel)
            labelLayer.addSublayer(node.labels)
            roots.append(node)
        }
        let geometry = RingGeometry(slotCount: count)
        for (i, node) in roots.enumerated() {
            let angle = geometry.centerAngle(of: i)
            let offset = geometry.offset(of: i, radius: Double(m.slotCenterRadius))
            let face = SlotFace(base.slots[i])
            node.centreOffset = centreOffset
            node.configure(face, placement: placement(angle: angle, offset: offset, origin: PolarPoint(angle: angle, radius: 0),
                                                      startScale: 0.25, labelFadeFrom: 0.7, style: style),
                           number: state.rootNumbers[i], style: style, now: now, motion: motion)
            let isAnchor = state.isFanned && state.anchor == i
            node.setShowsTab(!isAnchor, now: now, motion: motion)
            node.setDimmed(state.isFanned && !isAnchor, now: now, motion: motion)
            let lit = state.isFanned ? isAnchor : (state.highlighted == i || state.executing == i)
            node.setHighlight(lit ? 1 : 0, now: now, motion: motion)
            // Choosing a slot folds the rest of the ring away while it pulses.
            let folds = state.executing != nil && (state.isFanned || state.executing != i)
            if state.presented && !folds {
                let delay = motion.bloomDelay(index: i, count: count) * (1 - node.revealProgress(at: now))
                node.setReveal(1, curve: motion.bloom, delay: delay, now: now, motion: motion)
            } else {
                node.setReveal(0, curve: motion.collapse, now: now, motion: motion)
            }
            if !state.isFanned, state.executing == i, applied?.executing != i { node.firePulse(now: now, motion: motion) }
            let current = !state.isFanned
            syncLabels(node, index: i, isCurrentLevel: current, state: state, now: now, motion: motion)
        }
    }

    /// The tooltip (`.hub`) or caption chip (`.always`) of slot `index` of the shown level.
    private func syncLabels(_ node: ClassicBubbleNode, index: Int, isCurrentLevel: Bool, state: State, now: Double, motion: ClassicLayerMotion) {
        let filled = isCurrentLevel && state.levelFaces.indices.contains(index) && !state.levelFaces[index].isEmpty
        let tooltip = filled && state.labelMode == .hub && state.highlighted == index
        node.setTooltip(tooltip ? model.classicLabelPlacement(of: index, style: .tooltip) : nil, now: now, motion: motion)
        let chip = filled && state.labelMode == .always
        node.setChip(chip ? model.classicLabelPlacement(of: index, style: .chip) : nil, now: now, motion: motion)
    }

    // MARK: Folders

    private func syncFans(_ state: State, style: ClassicArtStyle, motion: ClassicLayerMotion, now: Double, newRing: Bool) {
        let target = state.fan
        if state.levelID != applied?.levelID {
            if newRing {
                for fan in fans { fan.nodes.forEach { $0.removeFromRing() } }
                fans.removeAll()
            }
            for fan in fans where fan.isOpen && fan.id != target?.id { fan.isOpen = false }
            if let target {
                if let fan = fans.first(where: { $0.id == target.id }) {
                    fan.isOpen = true
                    fan.ring = target.ring
                } else {
                    fans.append(Fan(id: target.id, ring: target.ring))
                }
            }
        }
        let m = state.metrics
        for fan in fans {
            let count = fan.ring.slotCount
            while fan.nodes.count > count { fan.nodes.removeLast().removeFromRing() }
            while fan.nodes.count < count {
                let node = ClassicBubbleNode()
                fanLayer.addSublayer(node.travel)
                labelLayer.addSublayer(node.labels)
                fan.nodes.append(node)
            }
            let isCurrent = fan.isOpen && fan.id == target?.id
            for (j, node) in fan.nodes.enumerated() {
                if isCurrent, let target {
                    let angle = target.arc.angle(of: j)
                    let origin = PolarPoint(angle: target.sourceAngle, radius: target.sourceIsRootSlot ? m.slotCenterRadius : m.folderRadius)
                    node.centreOffset = centreOffset
                    node.configure(SlotFace(fan.ring.slots[j]),
                                   placement: placement(angle: angle, offset: target.arc.offset(of: j, radius: Double(m.folderRadius)),
                                                        origin: origin, startScale: 0.5, labelFadeFrom: 0.6, style: style),
                                   number: state.levelNumbers.element(at: j) ?? nil, style: style, now: now, motion: motion)
                    node.setHighlight(state.highlighted == j || state.executing == j ? 1 : 0, now: now, motion: motion)
                    let folds = state.executing != nil && state.executing != j
                    if state.presented && !folds {
                        let delay = motion.fanDelay(index: j, count: count) * (1 - node.revealProgress(at: now))
                        node.setReveal(1, curve: motion.fanOut, delay: delay, now: now, motion: motion)
                    } else {
                        node.setReveal(0, curve: motion.collapse, now: now, motion: motion)
                    }
                    if state.executing == j, applied?.executing != j { node.firePulse(now: now, motion: motion) }
                    syncLabels(node, index: j, isCurrentLevel: true, state: state, now: now, motion: motion)
                } else {
                    node.setHighlight(0, now: now, motion: motion)
                    node.setReveal(0, curve: motion.fanIn, now: now, motion: motion)
                    syncLabels(node, index: j, isCurrentLevel: false, state: state, now: now, motion: motion)
                }
            }
        }
        // Fans that have folded away go; one still folding is checked again when it should be done.
        fans.removeAll { fan in
            guard !fan.isOpen, fan.nodes.allSatisfy({ $0.isGone(at: now) }) else { return false }
            fan.nodes.forEach { $0.removeFromRing() }
            return true
        }
        scheduleCleanup(now: now)
    }

    /// Asks for a sync once the last folding fan should have folded, to drop its layers.
    private func scheduleCleanup(now: Double) {
        cleanup?.cancel()
        let ends = fans.filter { !$0.isOpen }.flatMap(\.nodes).map(\.reveal.end)
        guard let end = ends.max() else { return }
        let wait = max(end - now, 0) + 0.05
        cleanup = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.needsLayout = true
        }
    }

    /// Renders the images of the folders' children (and of open folder slots) in idle time after
    /// a ring is set up, so opening a folder later costs nothing but the animation.
    private func prewarmFolders(of root: Ring, style: ClassicArtStyle, metrics m: RingMetrics) {
        prewarm?.cancel()
        prewarm = Task { [weak self] in
            let geometry = RingGeometry(slotCount: root.slotCount)
            for anchor in root.slots.indices {
                guard case .folder(let folder) = root.slots[anchor].action else { continue }
                _ = ClassicArtwork.shared.bubble(SlotFace(root.slots[anchor]), angle: geometry.centerAngle(of: anchor), showsTab: false, style: style)
                for ring in Self.levels(below: folder) {
                    await Task.yield()
                    guard !Task.isCancelled, self != nil else { return }
                    let arc = ArcGeometry(count: ring.slotCount, centerAngle: geometry.centerAngle(of: anchor), step: m.childStep)
                    for j in ring.slots.indices {
                        _ = ClassicArtwork.shared.bubble(SlotFace(ring.slots[j]), angle: arc.angle(of: j), showsTab: true, style: style)
                    }
                }
            }
        }
    }

    /// `folder` and every folder inside it, as shown with and without their gaps closed.
    private static func levels(below folder: Ring, depth: Int = 0) -> [Ring] {
        guard depth < 4 else { return [] }
        var rings = [folder]
        let compacted = folder.compacted().ring
        if compacted != folder { rings.append(compacted) }
        for slot in folder.slots {
            if case .folder(let inner) = slot.action { rings += levels(below: inner, depth: depth + 1) }
        }
        return rings
    }

    // MARK: Hub and shake

    private func syncHub(_ state: State, style: ClassicArtStyle, motion: ClassicLayerMotion, now: Double) {
        hub.configure(state.hub, rest: style.snapped(centreOffset), style: style, now: now, motion: motion)
        hub.setReveal(state.presented ? 1 : 0, curve: state.presented ? motion.hubBloom : motion.collapse, now: now, motion: motion)
    }

    /// Three decaying horizontal oscillations of the whole ring (`ShakeEffect`'s curve).
    private func shake(now: Double, motion: ClassicLayerMotion, unit: CGFloat) {
        let duration = motion.shakeDuration
        guard duration > 0 else { return }
        let amplitude = 6 * Double(unit)
        let count = Int(duration * LayerAnimation.samplesPerSecond) + 1
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = (0..<count).map { i in
            let phase = Double(i) / Double(count - 1)
            return NSNumber(value: amplitude * (1 - phase) * sin(phase * 2 * .pi * 3))
        }
        animation.beginTime = now
        animation.duration = duration
        animation.calculationMode = .linear
        shaker.add(animation, forKey: "shake")
    }
}

private extension Array {
    /// The element at `index`, or nil when out of range.
    func element(at index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
