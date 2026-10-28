import Foundation

/// A ring of slots. Slot 0 sits at the top; the rest follow clockwise.
public struct Ring: Codable, Hashable, Sendable {
    public static let slotRange = 4...12
    public static let defaultSlotCount = 8

    /// Always `slotRange`-sized; empty positions hold a `Slot` with a nil action.
    public private(set) var slots: [Slot]

    public init(slots: [Slot]) {
        self.slots = slots
        normalize()
    }

    public init(slotCount: Int = Ring.defaultSlotCount) {
        self.slots = (0..<Ring.clamp(slotCount)).map { _ in Slot() }
    }

    public var slotCount: Int { slots.count }
    public var filledCount: Int { slots.filter { $0.action != nil }.count }
    public var isEmpty: Bool { filledCount == 0 }

    public subscript(index: Int) -> Slot {
        get { slots[index] }
        set { slots[index] = newValue }
    }

    /// Changes the number of slots. Growing appends empty slots; shrinking drops empty slots first
    /// (from the end), then trailing filled ones, so filled slots move as little as possible.
    public mutating func resize(to newCount: Int) {
        let target = Ring.clamp(newCount)
        if target > slots.count {
            slots += (slots.count..<target).map { _ in Slot() }
        } else {
            while slots.count > target {
                if let emptyIndex = slots.lastIndex(where: { $0.action == nil }) {
                    slots.remove(at: emptyIndex)
                } else {
                    slots.removeLast()
                }
            }
        }
    }

    /// Swaps two slots (drag-to-reorder in the editor).
    public mutating func swapAt(_ i: Int, _ j: Int) {
        guard slots.indices.contains(i), slots.indices.contains(j) else { return }
        slots.swapAt(i, j)
    }

    /// Moves a slot to another position, shifting the others.
    public mutating func move(from i: Int, to j: Int) {
        guard slots.indices.contains(i), slots.indices.contains(j), i != j else { return }
        let slot = slots.remove(at: i)
        slots.insert(slot, at: j)
    }

    /// Clears a slot, keeping its position.
    public mutating func clear(_ i: Int) {
        guard slots.indices.contains(i) else { return }
        slots[i] = Slot()
    }

    /// Index of a slot by id.
    public func index(of id: Slot.ID) -> Int? { slots.firstIndex { $0.id == id } }

    /// The ring at a folder path (indices of folder slots from this ring downwards), or nil if the
    /// path no longer points at folders.
    public func ring(at path: [Int]) -> Ring? {
        var current = self
        for i in path {
            guard current.slots.indices.contains(i), case .folder(let inner) = current.slots[i].action else { return nil }
            current = inner
        }
        return current
    }

    /// Mutates the ring at a folder path in place. Returns false if the path is invalid.
    @discardableResult
    public mutating func updateRing(at path: [Int], _ body: (inout Ring) -> Void) -> Bool {
        guard let first = path.first else {
            body(&self)
            return true
        }
        guard slots.indices.contains(first), case .folder(var inner) = slots[first].action else { return false }
        let ok = inner.updateRing(at: Array(path.dropFirst()), body)
        if ok { slots[first].action = .folder(inner) }
        return ok
    }

    /// The filled slots only, evenly spread, for showing the live ring without gaps (a ring
    /// with 3 or 5 actions looks deliberate). `sourceIndices[i]` is where display slot `i` sits
    /// in this ring. A ring with no actions is returned as it is.
    public func compacted() -> CompactedRing {
        let filled = slots.indices.filter { slots[$0].action != nil }
        guard !filled.isEmpty, filled.count < slots.count else {
            return CompactedRing(ring: self, sourceIndices: Array(slots.indices))
        }
        return CompactedRing(ring: Ring(displaySlots: filled.map { slots[$0] }), sourceIndices: filled)
    }

    /// A display-only ring that may hold fewer than `slotRange.lowerBound` slots.
    private init(displaySlots: [Slot]) {
        self.slots = displaySlots
    }

    private mutating func normalize() {
        if slots.count < Ring.slotRange.lowerBound {
            slots += (slots.count..<Ring.slotRange.lowerBound).map { _ in Slot() }
        } else if slots.count > Ring.slotRange.upperBound {
            slots = Array(slots.prefix(Ring.slotRange.upperBound))
        }
        // Duplicate ids would break SwiftUI identity; regenerate any repeats.
        var seen = Set<UUID>()
        for i in slots.indices where !seen.insert(slots[i].id).inserted {
            slots[i].id = UUID()
        }
    }

    private static func clamp(_ n: Int) -> Int { min(max(n, slotRange.lowerBound), slotRange.upperBound) }

    private enum CodingKeys: String, CodingKey { case slots }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.slots = try c.decode([Slot].self, forKey: .slots)
        normalize()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(slots, forKey: .slots)
    }
}

/// A ring with its empty slots removed, and where each remaining slot came from.
public struct CompactedRing: Hashable, Sendable {
    public let ring: Ring
    /// For each slot of `ring`, its index in the original ring.
    public let sourceIndices: [Int]

    public init(ring: Ring, sourceIndices: [Int]) {
        self.ring = ring
        self.sourceIndices = sourceIndices
    }
}

/// One position on a ring.
public struct Slot: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var action: Action?
    /// Custom label; nil uses the action's default title.
    public var title: String?
    /// Custom icon; nil uses the action's default icon.
    public var icon: IconSpec?
    /// Custom accent for the highlight and icon backdrop; nil uses the theme accent.
    public var tint: RingColor?

    public init(id: UUID = UUID(), action: Action? = nil, title: String? = nil, icon: IconSpec? = nil, tint: RingColor? = nil) {
        self.id = id
        self.action = action
        self.title = title
        self.icon = icon
        self.tint = tint
    }

    public var isEmpty: Bool { action == nil }

    private enum CodingKeys: String, CodingKey { case id, action, title, icon, tint }

    /// Tolerant: an action or icon that fails to decode (e.g. from a newer version) leaves the
    /// slot empty instead of failing the whole config.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        self.action = try? c.decodeIfPresent(Action.self, forKey: .action)
        self.title = try? c.decodeIfPresent(String.self, forKey: .title)
        self.icon = try? c.decodeIfPresent(IconSpec.self, forKey: .icon)
        self.tint = try? c.decodeIfPresent(RingColor.self, forKey: .tint)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(action, forKey: .action)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encodeIfPresent(tint, forKey: .tint)
    }
}

/// How a slot's icon is drawn.
public enum IconSpec: Codable, Hashable, Sendable {
    /// An SF Symbol by name.
    case symbol(name: String)
    /// An application's icon, looked up by bundle ID.
    case app(bundleID: String)
    /// A custom image (PNG data, at most 256×256), embedded so exported configs stay portable.
    case image(png: Data)
    /// A single emoji or short glyph.
    case emoji(String)
}

/// Accent colours. Presets map to the system palette so they adapt to light/dark mode.
public enum RingColor: Codable, Hashable, Sendable {
    case preset(Preset)
    case custom(red: Double, green: Double, blue: Double)

    public enum Preset: String, Codable, CaseIterable, Sendable {
        case blue, indigo, purple, pink, red, orange, yellow, green, mint, teal, cyan, brown, graphite
    }
}
