import Foundation

/// The ring's input state machine, free of UI so it can be tested.
///
/// The overlay feeds it trigger presses/releases, pointer moves (already mapped to a slot index),
/// clicks and keys, and applies the returned effects (show, highlight, run, enter folder…).
/// It supports both ways of using the trigger:
/// - tap: the ring stays open; click a slot, press 1–9, or press the trigger again on a slot;
/// - hold: point at a slot and release to run it; release in the centre to cancel.
public struct RingInteraction: Sendable {
    public enum Phase: Equatable, Sendable {
        case closed
        /// Trigger is down; the ring opened at `since` (seconds, any monotonic clock).
        case holding(since: TimeInterval)
        /// Ring stays open until something is chosen or it is dismissed.
        case open
    }

    /// What occupies each slot of the ring level currently shown.
    public enum SlotKind: Equatable, Sendable {
        case empty, action, folder
    }

    public enum Effect: Equatable, Sendable {
        /// Show the ring (at the pointer) with the root level.
        case show
        /// Dismiss without running anything.
        case dismiss
        case highlight(Int?)
        /// Run the slot's action at the current level, then dismiss.
        case execute(Int)
        /// Replace the current level with the folder at this slot.
        case enterFolder(Int)
        /// Return to the parent level.
        case exitFolder
        /// The slot can't be chosen (it is empty): give "nope" feedback, stay open.
        case reject(Int)
    }

    public var mode: SelectionMode
    public var holdThreshold: TimeInterval

    public private(set) var phase: Phase = .closed
    public private(set) var highlighted: Int?
    /// Folder depth of the level shown (0 = root).
    public private(set) var depth = 0
    private var level: [SlotKind] = []

    public init(mode: SelectionMode = .auto, holdThreshold: TimeInterval = 0.28) {
        self.mode = mode
        self.holdThreshold = holdThreshold
    }

    public var isOpen: Bool { phase != .closed }

    /// Tells the machine what the shown level contains. Call after `.show`, `.enterFolder` and
    /// `.exitFolder` (and whenever the shown ring changes).
    public mutating func setLevel(_ kinds: [SlotKind]) {
        level = kinds
        if let h = highlighted, !kinds.indices.contains(h) { highlighted = nil }
    }

    // MARK: Trigger

    public mutating func triggerDown(at time: TimeInterval) -> [Effect] {
        switch phase {
        case .closed:
            phase = .holding(since: time)
            highlighted = nil
            depth = 0
            return [.show]
        case .holding:
            // Key auto-repeat or a duplicate press: ignore.
            return []
        case .open:
            // Second press: run what is highlighted, or toggle the ring closed.
            if let h = highlighted { return activate(h) }
            return close()
        }
    }

    public mutating func triggerUp(at time: TimeInterval) -> [Effect] {
        guard case .holding(let since) = phase else { return [] }
        let heldLongEnough = time - since >= holdThreshold
        switch mode {
        case .tapThenClick:
            phase = .open
            return []
        case .holdAndRelease:
            if let h = highlighted { return activateOnRelease(h) }
            return close()
        case .auto:
            if let h = highlighted { return activateOnRelease(h) }
            if heldLongEnough { return close() }
            phase = .open
            return []
        }
    }

    // MARK: Pointer

    /// The pointer now points at `slot` (nil = centre/outside).
    public mutating func pointerMoved(toSlot slot: Int?) -> [Effect] {
        guard isOpen else { return [] }
        let s = slot.flatMap { level.indices.contains($0) ? $0 : nil }
        guard s != highlighted else { return [] }
        highlighted = s
        return [.highlight(s)]
    }

    /// A click on a slot, on the hub (`slot == nil, inHub == true`) or outside the ring.
    public mutating func click(slot: Int?, inHub: Bool = false) -> [Effect] {
        guard isOpen else { return [] }
        if let slot { return activate(slot) }
        if inHub, depth > 0 { return exitFolder() }
        return close()
    }

    // MARK: Keyboard

    public mutating func escape() -> [Effect] {
        guard isOpen else { return [] }
        return depth > 0 ? exitFolder() : close()
    }

    /// Delete/Backspace: back out of a folder; does nothing at the root.
    public mutating func back() -> [Effect] {
        guard isOpen, depth > 0 else { return [] }
        return exitFolder()
    }

    /// Number keys: 1 is slot 0 … 9 is slot 8, 0 is slot 9.
    public mutating func number(_ n: Int) -> [Effect] {
        guard isOpen else { return [] }
        let index = n == 0 ? 9 : n - 1
        guard level.indices.contains(index) else { return [] }
        return activate(index)
    }

    /// The pointer rested on `slot` briefly (the caller times the dwell). Hovering a folder opens
    /// it without a click, like a submenu: while holding, nested actions are reached in one
    /// stroke; in tap mode the folder simply opens.
    public mutating func dwell(on slot: Int) -> [Effect] {
        guard isOpen, highlighted == slot, level.indices.contains(slot), level[slot] == .folder else { return [] }
        depth += 1
        highlighted = nil
        // Keep the phase: while holding, releasing over a slot of the folder runs it.
        return [.enterFolder(slot), .highlight(nil)]
    }

    /// Moves the highlight (arrow keys / Tab), computed by the caller with `RingGeometry`.
    public mutating func setHighlight(_ slot: Int?) -> [Effect] {
        pointerMoved(toSlot: slot)
    }

    /// Return/Space: run the highlighted slot.
    public mutating func confirm() -> [Effect] {
        guard isOpen, let h = highlighted else { return [] }
        return activate(h)
    }

    /// Dismiss from outside (e.g. the user switched Spaces or the screen locked).
    public mutating func cancel() -> [Effect] {
        guard isOpen else { return [] }
        return close()
    }

    // MARK: Internals

    private mutating func activateOnRelease(_ index: Int) -> [Effect] {
        // Releasing over an empty slot cancels rather than leaving a ring open that the user
        // was clearly done with.
        if level.indices.contains(index), level[index] == .empty { return close() }
        return activate(index)
    }

    private mutating func activate(_ index: Int) -> [Effect] {
        guard level.indices.contains(index) else { return [] }
        switch level[index] {
        case .empty:
            if case .holding = phase { phase = .open }
            return [.reject(index)]
        case .folder:
            depth += 1
            phase = .open
            highlighted = nil
            return [.enterFolder(index), .highlight(nil)]
        case .action:
            reset()
            return [.execute(index)]
        }
    }

    private mutating func exitFolder() -> [Effect] {
        depth -= 1
        highlighted = nil
        // Going back while the trigger is held keeps holding, so a hover-switch to another root
        // slot can still be released to run it.
        if case .holding = phase {} else { phase = .open }
        return [.exitFolder, .highlight(nil)]
    }

    private mutating func close() -> [Effect] {
        reset()
        return [.dismiss]
    }

    private mutating func reset() {
        phase = .closed
        highlighted = nil
        depth = 0
        level = []
    }
}
