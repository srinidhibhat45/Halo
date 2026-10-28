import Testing
@testable import HaloCore

@Suite("RingInteraction")
struct RingInteractionTests {
    /// 8 slots: 0-5 actions, 6 folder, 7 empty.
    let level: [RingInteraction.SlotKind] = [.action, .action, .action, .action, .action, .action, .folder, .empty]

    func opened(_ mode: SelectionMode = .auto) -> RingInteraction {
        var r = RingInteraction(mode: mode, holdThreshold: 0.3)
        #expect(r.triggerDown(at: 0) == [.show])
        r.setLevel(level)
        return r
    }

    @Test("Quick tap keeps the ring open")
    func tapSticks() {
        var r = opened()
        #expect(r.triggerUp(at: 0.1) == [])
        #expect(r.phase == .open)
    }

    @Test("Hold, point, release runs the slot")
    func holdRelease() {
        var r = opened()
        #expect(r.pointerMoved(toSlot: 2) == [.highlight(2)])
        #expect(r.triggerUp(at: 0.6) == [.execute(2)])
        #expect(r.phase == .closed)
    }

    @Test("A fast flick then release still runs (mark-ahead)")
    func flick() {
        var r = opened()
        _ = r.pointerMoved(toSlot: 4)
        #expect(r.triggerUp(at: 0.12) == [.execute(4)])
    }

    @Test("Holding, then releasing in the centre cancels")
    func holdCancel() {
        var r = opened()
        #expect(r.triggerUp(at: 0.8) == [.dismiss])
        #expect(!r.isOpen)
    }

    @Test("Releasing over an empty slot cancels")
    func releaseOnEmpty() {
        var r = opened()
        _ = r.pointerMoved(toSlot: 7)
        #expect(r.triggerUp(at: 0.8) == [.dismiss])
    }

    @Test("Clicking an empty slot rejects and stays open")
    func clickEmpty() {
        var r = opened()
        _ = r.triggerUp(at: 0.1)
        #expect(r.click(slot: 7) == [.reject(7)])
        #expect(r.phase == .open)
    }

    @Test("Second press runs the highlighted slot, or closes")
    func secondPress() {
        var r = opened()
        _ = r.triggerUp(at: 0.1)
        _ = r.pointerMoved(toSlot: 1)
        #expect(r.triggerDown(at: 1.0) == [.execute(1)])
        #expect(r.triggerUp(at: 1.1) == [])

        var s = opened()
        _ = s.triggerUp(at: 0.1)
        #expect(s.triggerDown(at: 1.0) == [.dismiss])
    }

    @Test("Key auto-repeat is ignored while holding")
    func autoRepeat() {
        var r = opened()
        #expect(r.triggerDown(at: 0.05) == [])
        #expect(r.phase == .holding(since: 0))
    }

    @Test("Folders: enter on release, back with Escape, close at root")
    func folders() {
        var r = opened()
        _ = r.pointerMoved(toSlot: 6)
        #expect(r.triggerUp(at: 0.7) == [.enterFolder(6), .highlight(nil)])
        #expect(r.phase == .open)
        #expect(r.depth == 1)
        r.setLevel([.action, .action, .action, .action])
        #expect(r.escape() == [.exitFolder, .highlight(nil)])
        #expect(r.depth == 0)
        r.setLevel(level)
        #expect(r.escape() == [.dismiss])
    }

    @Test("Clicking the hub inside a folder goes back; at the root it closes")
    func hub() {
        var r = opened()
        _ = r.triggerUp(at: 0.1)
        _ = r.click(slot: 6)
        r.setLevel([.action, .action, .action, .action])
        #expect(r.click(slot: nil, inHub: true) == [.exitFolder, .highlight(nil)])
        r.setLevel(level)
        #expect(r.click(slot: nil, inHub: true) == [.dismiss])
    }

    @Test("Number keys pick slots; 0 is the tenth")
    func numbers() {
        var r = opened()
        _ = r.triggerUp(at: 0.1)
        #expect(r.number(3) == [.execute(2)])

        var s = opened()
        #expect(s.number(0) == [])   // only 8 slots
        #expect(s.number(9) == [])
    }

    @Test("Return runs the highlight; nothing highlighted does nothing")
    func confirm() {
        var r = opened()
        _ = r.triggerUp(at: 0.1)
        #expect(r.confirm() == [])
        _ = r.setHighlight(5)
        #expect(r.confirm() == [.execute(5)])
    }

    @Test("Tap-then-click never runs on release")
    func tapMode() {
        var r = opened(.tapThenClick)
        _ = r.pointerMoved(toSlot: 2)
        #expect(r.triggerUp(at: 1.0) == [])
        #expect(r.phase == .open)
        #expect(r.click(slot: 2) == [.execute(2)])
    }

    @Test("Hold-and-release cancels a tap with nothing highlighted")
    func holdMode() {
        var r = opened(.holdAndRelease)
        #expect(r.triggerUp(at: 0.05) == [.dismiss])
    }

    @Test("Pointer moves only report changes and ignore out-of-range slots")
    func pointer() {
        var r = opened()
        #expect(r.pointerMoved(toSlot: 3) == [.highlight(3)])
        #expect(r.pointerMoved(toSlot: 3) == [])
        #expect(r.pointerMoved(toSlot: 42) == [.highlight(nil)])
    }

    @Test("Dwelling on a folder while holding opens it and keeps holding")
    func dwellOpensFolder() {
        var r = opened()
        _ = r.pointerMoved(toSlot: 6)
        #expect(r.dwell(on: 6) == [.enterFolder(6), .highlight(nil)])
        #expect(r.depth == 1)
        r.setLevel([.action, .action, .action, .action])
        _ = r.pointerMoved(toSlot: 2)
        #expect(r.triggerUp(at: 1.2) == [.execute(2)])
    }

    @Test("Dwell does nothing on actions or off the highlight")
    func dwellIgnored() {
        var r = opened()
        _ = r.pointerMoved(toSlot: 1)
        #expect(r.dwell(on: 1) == [])
        #expect(r.dwell(on: 6) == [])
    }

    @Test("Hovering a folder in tap mode opens it and stays in tap mode")
    func dwellInTapMode() {
        var r = opened()
        _ = r.triggerUp(at: 0.1)   // now sticky
        _ = r.pointerMoved(toSlot: 6)
        #expect(r.dwell(on: 6) == [.enterFolder(6), .highlight(nil)])
        #expect(r.phase == .open)
        #expect(r.depth == 1)
    }

    @Test("Backing out of a folder while holding keeps holding, so release still runs")
    func backWhileHolding() {
        var r = opened()
        _ = r.pointerMoved(toSlot: 6)
        _ = r.dwell(on: 6)
        r.setLevel([.action, .action, .action, .action])
        #expect(r.back() == [.exitFolder, .highlight(nil)])
        #expect(r.phase == .holding(since: 0))
        r.setLevel(level)
        _ = r.pointerMoved(toSlot: 2)
        #expect(r.triggerUp(at: 1.0) == [.execute(2)])
    }

    @Test("Clicking outside closes")
    func outside() {
        var r = opened()
        _ = r.triggerUp(at: 0.1)
        #expect(r.click(slot: nil) == [.dismiss])
    }
}
