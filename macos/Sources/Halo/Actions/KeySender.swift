import AppKit
import Carbon.HIToolbox
import HaloCore

/// Synthesizes keyboard input for the frontmost app.
///
/// Events go to the HID tap (so system shortcuts such as ⌃⌘Q or ⇧⌘4 fire) with explicit flags,
/// wrapped in real modifier key events (some apps only honour modifiers they saw go down), and
/// carry `eventTag` so Halo can recognise its own events. Needs Accessibility; without it macOS
/// drops posted events silently, so callers check first.
enum KeySender {
    /// Stored in `eventSourceUserData` of every event Halo posts ("HALO").
    static let eventTag: Int64 = 0x4841_4C4F

    private static let standardModifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]

    /// Modifier keys in the order they go down (and, reversed, come up).
    private static let modifierKeys: [(flag: CGEventFlags, keyCode: CGKeyCode)] = [
        (.maskControl, CGKeyCode(kVK_Control)),
        (.maskAlternate, CGKeyCode(kVK_Option)),
        (.maskShift, CGKeyCode(kVK_Shift)),
        (.maskCommand, CGKeyCode(kVK_Command)),
    ]

    /// Longest Unicode run per typed event; longer strings are dropped by some apps.
    private static let typingChunk = 20

    // MARK: Waiting for the trigger

    /// Waits (at most 300 ms) until the modifiers of the ring's trigger are physically released, so
    /// they don't leak into the shortcut we post. Returns at once in tap mode, where they are up.
    static func waitForTriggerRelease() async {
        let watched = AppModel.shared.settings.trigger.map { $0.modifiers.cgEventFlags.intersection(standardModifiers) }
            ?? standardModifiers
        guard !watched.isEmpty else { return }
        let deadline = ContinuousClock.now + .milliseconds(300)
        while !CGEventSource.flagsState(.combinedSessionState).intersection(watched).isEmpty, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: Pressing keys

    /// Presses a recorded combo (physical key code). The Fn/Globe flag is dropped: it can't trigger
    /// Globe shortcuts and turns arrows into Home/End.
    @discardableResult
    static func press(_ combo: KeyCombo) async -> Bool {
        await press(CGKeyCode(combo.keyCode), modifiers: combo.modifiers.cgEventFlags)
    }

    /// Presses the key that types `character` in the current keyboard layout (resolved with ⌘ held
    /// when `modifiers` contains it, so "Dvorak – QWERTY ⌘" works), falling back to `fallback`.
    @discardableResult
    static func press(character: Character, modifiers: CGEventFlags, fallback: CGKeyCode) async -> Bool {
        let code = keyCode(for: character, command: modifiers.contains(.maskCommand)) ?? fallback
        return await press(code, modifiers: modifiers)
    }

    /// Presses `keyCode` with exactly `modifiers` (⌃⌥⇧⌘ only).
    @discardableResult
    static func press(_ keyCode: CGKeyCode, modifiers: CGEventFlags) async -> Bool {
        guard let source = makeSource() else { return false }
        let flags = modifiers.intersection(standardModifiers)
        let mods = modifierKeys.filter { flags.contains($0.flag) }
        var held: CGEventFlags = []
        for mod in mods {
            held.insert(mod.flag)
            post(mod.keyCode, down: true, flags: held, source: source)
        }
        post(keyCode, down: true, flags: flags, source: source)
        try? await Task.sleep(for: .milliseconds(4))
        post(keyCode, down: false, flags: flags, source: source)
        for mod in mods.reversed() {
            held.remove(mod.flag)
            post(mod.keyCode, down: false, flags: held, source: source)
        }
        return true
    }

    // MARK: Typing text

    /// Types `text` as Unicode key events in grapheme-safe chunks; newlines and tabs become real
    /// Return and Tab presses.
    @discardableResult
    static func type(_ text: String) async -> Bool {
        guard let source = makeSource() else { return false }
        var pending: [UniChar] = []
        for character in text {
            if character.isNewline || character == "\t" {
                await typeChunk(&pending, source: source)
                let key = character == "\t" ? CGKeyCode(kVK_Tab) : CGKeyCode(kVK_Return)
                post(key, down: true, flags: [], source: source)
                post(key, down: false, flags: [], source: source)
                try? await Task.sleep(for: .milliseconds(4))
                continue
            }
            let units = Array(String(character).utf16)
            if !pending.isEmpty, pending.count + units.count > typingChunk {
                await typeChunk(&pending, source: source)
            }
            pending += units
        }
        await typeChunk(&pending, source: source)
        return true
    }

    private static func typeChunk(_ units: inout [UniChar], source: CGEventSource) async {
        guard !units.isEmpty else { return }
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
            units.withUnsafeBufferPointer { event.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress) }
            event.flags = []
            event.post(tap: .cghidEventTap)
        }
        units.removeAll(keepingCapacity: true)
        try? await Task.sleep(for: .milliseconds(4))
    }

    // MARK: Event plumbing

    private static func makeSource() -> CGEventSource? {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            Log.actions.error("Could not create an event source")
            return nil
        }
        source.userData = eventTag
        // The default 0.25 s would swallow the user's own keystrokes right after ours.
        source.localEventsSuppressionInterval = 0
        return source
    }

    private static func post(_ keyCode: CGKeyCode, down: Bool, flags: CGEventFlags, source: CGEventSource) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { return }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    // MARK: Layout-aware key codes

    private struct LayoutMap {
        var sourceID: String
        var plain: [Character: CGKeyCode]
        var command: [Character: CGKeyCode]
    }

    private static var layoutMap: LayoutMap?

    /// The key code that produces `character` in the current layout, or nil if none does.
    private static func keyCode(for character: Character, command: Bool) -> CGKeyCode? {
        guard let source = currentLayoutSource() else { return nil }
        let id = stringProperty(source, kTISPropertyInputSourceID) ?? ""
        if layoutMap?.sourceID != id {
            layoutMap = LayoutMap(sourceID: id, plain: characterMap(source, modifiers: 0),
                                  command: characterMap(source, modifiers: (UInt32(cmdKey) >> 8) & 0xFF))
        }
        let key = character.lowercased().first ?? character
        return command ? (layoutMap?.command[key] ?? layoutMap?.plain[key]) : layoutMap?.plain[key]
    }

    /// The current keyboard layout, or the ASCII-capable one for input methods without layout data.
    private static func currentLayoutSource() -> TISInputSource? {
        let candidates = [TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
                          TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue()]
        return candidates.compactMap { $0 }.first { TISGetInputSourceProperty($0, kTISPropertyUnicodeKeyLayoutData) != nil }
    }

    private static func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    /// Lowercased character → first (lowest) key code that types it with the given Carbon modifiers.
    private static func characterMap(_ source: TISInputSource, modifiers: UInt32) -> [Character: CGKeyCode] {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return [:] }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        return data.withUnsafeBytes { buffer -> [Character: CGKeyCode] in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return [:] }
            var map: [Character: CGKeyCode] = [:]
            for code in UInt16(0)..<128 {
                var deadKeyState: UInt32 = 0
                var chars = [UniChar](repeating: 0, count: 4)
                var length = 0
                let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), modifiers, UInt32(LMGetKbdType()),
                                            OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState, chars.count, &length, &chars)
                guard status == noErr, length > 0,
                      let character = String(utf16CodeUnits: chars, count: length).lowercased().first else { continue }
                if map[character] == nil { map[character] = CGKeyCode(code) }
            }
            return map
        }
    }
}
