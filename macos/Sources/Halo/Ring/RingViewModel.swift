import HaloCore
import Observation
import SwiftUI

/// Everything `RingView` draws, for both the live overlay and the configurator's preview.
///
/// The overlay controller (live) and the ring editor (editor/preview) own an instance and mutate
/// it; `RingView` only reads it and animates between states.
@Observable
final class RingViewModel {
    enum Mode: Equatable {
        /// The real overlay: hover highlight, appear/dismiss animation.
        case live
        /// Configurator canvas: shows `selected`, empty-slot "+" affordances, no appear animation.
        case editor
        /// Static thumbnail (e.g. theme picker); no interaction.
        case preview
    }

    /// How the current level arrived, so the view can animate folder navigation.
    enum LevelTransition: Equatable {
        case none
        /// Entered a nested ring from the slot at this index of the parent.
        case push(fromSlot: Int)
        /// Went back to the parent; `toSlot` is the folder slot we came out of.
        case pop(toSlot: Int)
    }

    /// A folder level entered from the level below it.
    struct LevelEntry: Equatable {
        /// The ring that was showing before the folder opened.
        var ring: Ring
        /// The slot of that ring that opened the folder.
        var slot: Int
    }

    /// What a pointer position is over.
    enum HitTarget: Equatable {
        /// A slot of the current level.
        case slot(Int)
        /// The centre hub (close, or back when inside a folder).
        case hub
        /// A slot of the root ring while a folder is fanned out over it.
        case rootSlot(Int)
        /// Nothing (dead zone, outside the ring, outside a folder's arc).
        case none
    }

    /// Identifies the app whose ring is shown, for the hub badge.
    struct AppBadge: Equatable {
        var bundleID: String
        var name: String
    }

    var mode: Mode

    // Content
    /// The level currently shown (root ring or a nested ring).
    var ring: Ring
    /// Titles of folders entered, root first (empty at the root).
    var breadcrumb: [String] = []
    /// Folder levels entered, oldest first; maintained by `showLevel`. Empty at the root.
    private(set) var levelStack: [LevelEntry] = []
    var levelTransition: LevelTransition = .none
    /// Bumped on every level change so views can key transitions on it.
    var levelID = 0
    var appBadge: AppBadge?

    // Interaction state
    var highlighted: Int?
    /// Editor selection (the slot being edited).
    var selected: Int?
    /// Slot that was just rejected (empty); with `rejectCount` so repeated rejects re-animate.
    var rejected: Int?
    var rejectCount = 0
    /// Slot that was just chosen; drives the "fire" flash before dismissal.
    var executing: Int?
    /// Drives the appear (true) and dismiss (false) animations in `.live` mode.
    var isPresented = false
    /// True while the trigger is held (hold mode), for subtle "armed" styling.
    var isHolding = false
    /// Live tap mode: the pointer is over the hub, so a click there closes (or goes back).
    var isHubHovered = false
    /// Editor: slot currently under a drag-and-drop hover.
    var dropTarget: Int?
    /// Editor: slot being dragged (drawn lifted).
    var dragSource: Int?
    /// Editor: slots of an app ring that show the Everywhere ring's action (drawn ghosted).
    var inheritedSlots: Set<Int> = []

    // Appearance (copied from settings when the ring opens / settings change)
    var theme: RingTheme
    var scale: Double
    var labelMode: LabelMode
    var accent: RingColor
    var showNumbers: Bool
    /// 0 disables animation; Reduce Motion is applied by the view on top of this.
    var animationSpeed: Double

    init(mode: Mode, ring: Ring, settings: AppSettings) {
        self.mode = mode
        self.ring = ring
        self.theme = settings.theme
        self.scale = settings.ringScale
        self.labelMode = settings.labelMode
        self.accent = settings.accent
        self.showNumbers = settings.showSlotNumbers
        self.animationSpeed = settings.animationSpeed
    }

    /// Copies appearance settings.
    func apply(_ settings: AppSettings) {
        theme = settings.theme
        scale = settings.ringScale
        labelMode = settings.labelMode
        accent = settings.accent
        showNumbers = settings.showSlotNumbers
        animationSpeed = settings.animationSpeed
    }

    /// Metrics for the ring on screen (the root ring while a folder is fanned out over it).
    var metrics: RingMetrics { RingMetrics(theme: theme, scale: scale, slotCount: (isFanned ? (rootRing ?? ring) : ring).slotCount) }
    /// Geometry of the shown level when it is a full ring (not fanned).
    var geometry: RingGeometry { RingGeometry(slotCount: ring.slotCount) }

    /// The slot whose name the hub shows: highlighted (live) or selected (editor).
    var focusedSlot: Int? { mode == .editor ? (highlighted ?? selected) : highlighted }

    /// The root ring while a folder is open (drawn dimmed, with the folder's children fanned out
    /// beyond it), else nil.
    var rootRing: Ring? { levelStack.first?.ring }

    /// The root slot the open folder hangs from, else nil.
    var folderAnchor: Int? { levelStack.first?.slot }

    /// True while a folder's children are fanned out over the root ring (live overlay only; the
    /// editor shows one level at a time).
    var isFanned: Bool { mode == .live && folderAnchor != nil }

    /// Layout of the fanned-out children of the current level, if fanned.
    var childArc: ArcGeometry? {
        guard isFanned, let anchor = folderAnchor, let root = rootRing, ring.slotCount > 0 else { return nil }
        let rootGeometry = RingGeometry(slotCount: root.slotCount)
        return ArcGeometry(count: ring.slotCount, centerAngle: rootGeometry.centerAngle(of: anchor), step: metrics.childStep)
    }

    /// Replaces the shown level, recording how we got there. `.none` starts over at a root ring.
    func showLevel(_ ring: Ring, transition: LevelTransition) {
        switch transition {
        case .none: levelStack.removeAll()
        case .push(let slot): levelStack.append(LevelEntry(ring: self.ring, slot: slot))
        case .pop: if !levelStack.isEmpty { levelStack.removeLast() }
        }
        self.ring = ring
        self.levelTransition = transition
        self.highlighted = nil
        self.levelID += 1
    }

    /// Classifies a pointer offset from the ring centre (y-down points, as in SwiftUI).
    ///
    /// - `holding`: the trigger is held (marking-menu mode): small dead zone, unbounded reach,
    ///   the hub is not a target.
    /// - `current`: the currently highlighted slot, for hysteresis.
    func hitTest(dx: Double, dy: Double, holding: Bool, current: Int?) -> HitTarget {
        let m = metrics
        let r = (dx * dx + dy * dy).squareRoot()
        if !holding, r <= Double(m.hubRadius) { return .hub }

        if let arc = childArc, let root = rootRing {
            // Children live beyond the midpoint between the root ring and the folder ring.
            let minRadius = Double(m.slotCenterRadius + m.folderRadius) / 2
            if r < minRadius {
                // Over the dimmed root ring: hovering another root slot switches to it (like a
                // menu bar), in both modes. The centre stays inert.
                let inner = Double(holding ? m.holdDeadZone : m.hubRadius)
                guard r > inner else { return .none }
                let rootGeometry = RingGeometry(slotCount: root.slotCount)
                return rootGeometry.slot(dx: dx, dy: dy, deadZone: inner, maxRadius: minRadius).map(HitTarget.rootSlot) ?? .none
            }
            let maxRadius = holding ? nil : Double(m.folderRadius + m.slotSize / 2 + 60)
            return arc.slot(dx: dx, dy: dy, minRadius: minRadius, maxRadius: maxRadius).map(HitTarget.slot) ?? .none
        }

        let deadZone = Double(holding ? m.holdDeadZone : m.tapDeadZone)
        let maxRadius = holding ? nil : Double(m.maxHitRadius)
        return geometry.slot(dx: dx, dy: dy, deadZone: deadZone, maxRadius: maxRadius, current: current, hysteresis: m.hysteresis)
            .map(HitTarget.slot) ?? .none
    }

    /// Where slot `index` of the shown level is drawn, as an offset from the ring centre
    /// (y-down): on the ring, or on the folder arc when fanned.
    func slotOffset(_ index: Int) -> CGPoint {
        let m = metrics
        if let arc = childArc { return arc.offset(of: index, radius: Double(m.folderRadius)) }
        return geometry.offset(of: index, radius: Double(m.slotCenterRadius))
    }

    func reject(_ index: Int) {
        rejected = index
        rejectCount += 1
    }
}
