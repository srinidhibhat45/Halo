import AppKit
import HaloCore

/// One showing of the live ring: the ring resolved when it opened (edits made meanwhile apply
/// next time), where it is on screen, the app it acts on, and the folders entered so far.
///
/// With `closesGaps`, every level shows only its filled slots, evenly spread; indices used here
/// (and by the state machine and view model) are display indices, mapped back to configured
/// positions through `sourceIndices` for editing.
struct RingSession {
    /// A nested ring entered from a folder slot.
    struct Level {
        /// The level as shown.
        var ring: Ring
        var title: String
        /// Display index of the folder slot in the parent level.
        var indexInParent: Int
        /// For each displayed slot, its index in the configured folder ring.
        var sourceIndices: [Int]
    }

    /// The root ring as shown (global or app-specific, inherited slots filled in, gaps closed).
    let root: Ring
    /// For each displayed root slot, its index in the configured ring.
    let rootSourceIndices: [Int]
    /// The resolved root ring before gaps were closed.
    let resolvedRoot: Ring
    /// Whether empty slots are left out of every level.
    let closesGaps: Bool
    /// Which configured ring `root` came from.
    let target: RingTarget
    /// For an app ring: the profile's own ring, before inheritance, to tell inherited slots apart.
    let profileRing: Ring?
    /// Spoken when the ring opens ("Halo", or the app's name for an app ring).
    let title: String
    /// The app that was frontmost when the ring opened; actions apply to it.
    let frontmostApp: NSRunningApplication?
    /// The panel's frame, in screen coordinates (AppKit, y-up). The ring is centred in it.
    let frame: CGRect
    /// Where the pointer was when the ring opened (screen coordinates). Strokes made while the
    /// trigger is held are measured from here, wherever the ring itself ended up.
    let pressPoint: CGPoint
    /// When the ring opened (`HotKeyCenter.now`'s clock).
    let openedAt: TimeInterval
    private(set) var stack: [Level] = []

    init(root: Ring, closesGaps: Bool, target: RingTarget, profileRing: Ring?, title: String, frontmostApp: NSRunningApplication?,
         frame: CGRect, pressPoint: CGPoint, openedAt: TimeInterval) {
        let shown = Self.display(root, closesGaps: closesGaps)
        self.resolvedRoot = root
        self.root = shown.ring
        self.rootSourceIndices = shown.sourceIndices
        self.closesGaps = closesGaps
        self.target = target
        self.profileRing = profileRing
        self.title = title
        self.frontmostApp = frontmostApp
        self.frame = frame
        self.pressPoint = pressPoint
        self.openedAt = openedAt
    }

    /// The ring's centre in screen coordinates; slot angles are measured from here.
    var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }

    /// The level currently shown.
    var current: Ring { stack.last?.ring ?? root }

    /// Titles of the folders entered, root first.
    var breadcrumb: [String] { stack.map(\.title) }

    func slot(at index: Int) -> Slot? {
        current.slots.indices.contains(index) ? current.slots[index] : nil
    }

    /// Enters the folder at `index` of the current level; nil if that slot isn't a folder.
    mutating func enterFolder(at index: Int) -> Ring? {
        guard let slot = slot(at: index), case .folder(let inner)? = slot.action else { return nil }
        let shown = Self.display(inner, closesGaps: closesGaps)
        stack.append(Level(ring: shown.ring, title: slot.displayTitle, indexInParent: index, sourceIndices: shown.sourceIndices))
        return shown.ring
    }

    /// `ring` as shown: compacted when closing gaps.
    private static func display(_ ring: Ring, closesGaps: Bool) -> CompactedRing {
        closesGaps ? ring.compacted() : CompactedRing(ring: ring, sourceIndices: Array(ring.slots.indices))
    }

    /// Returns to the parent level: the parent ring and the folder slot we came out of.
    mutating func exitFolder() -> (ring: Ring, folderSlot: Int)? {
        guard let left = stack.popLast() else { return nil }
        return (current, left.indexInParent)
    }

    /// Where ⌘-click opens the configurator: the current level, with `slot` selected. Slots an
    /// app ring inherits from the global ring (and folders inside them) are edited there.
    func editDestination(slot: Int?) -> SettingsDestination {
        // Display indices → configured indices, level by level.
        var parentSources = rootSourceIndices
        var path: [Int] = []
        for level in stack {
            path.append(parentSources.indices.contains(level.indexInParent) ? parentSources[level.indexInParent] : level.indexInParent)
            parentSources = level.sourceIndices
        }
        let slot = slot.map { parentSources.indices.contains($0) ? parentSources[$0] : $0 }
        var target = self.target
        if let profileRing, let rootIndex = path.first ?? slot,
           profileRing.slots.indices.contains(rootIndex), resolvedRoot.slots.indices.contains(rootIndex),
           profileRing.slots[rootIndex].action == nil, resolvedRoot.slots[rootIndex].action != nil {
            target = .global
        }
        return .ring(target, path: path, slot: slot)
    }

    /// What each slot of `ring` holds, for `RingInteraction.setLevel`.
    static func kinds(of ring: Ring) -> [RingInteraction.SlotKind] {
        ring.slots.map { slot in
            guard let action = slot.action else { return .empty }
            return action.isFolder ? .folder : .action
        }
    }

    /// The most slots on any level of `ring` (root or nested), so the panel fits every level.
    static func largestSlotCount(in ring: Ring) -> Int {
        ring.slots.reduce(ring.slotCount) { largest, slot in
            guard case .folder(let inner)? = slot.action else { return largest }
            return max(largest, largestSlotCount(in: inner))
        }
    }
}
