import AppKit
import Carbon.HIToolbox
import HaloCore

/// Key labels in the user's current keyboard layout, and modifier conversions between HaloCore,
/// AppKit, Carbon and Quartz event representations.
enum KeyboardLayout {
    /// What the key shows in the current layout: "H", "Space", "F5", "↩"…
    static func label(forKeyCode code: UInt16) -> String {
        if let special = KeyCode.specialLabel(for: code) { return special }
        if let text = translate(code)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text.uppercased()
        }
        return "Key \(code)"
    }

    /// A `KeyCombo` from a key event (used by the shortcut recorder).
    static func combo(from event: NSEvent) -> KeyCombo {
        KeyCombo(keyCode: event.keyCode, modifiers: Modifiers(event.modifierFlags), keyLabel: label(forKeyCode: event.keyCode))
    }

    /// The key's character in the current layout, ignoring modifiers.
    private static func translate(_ code: UInt16) -> String? {
        let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
        let fallback = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue()
        for candidate in [source, fallback].compactMap({ $0 }) {
            guard let raw = TISGetInputSourceProperty(candidate, kTISPropertyUnicodeKeyLayoutData) else { continue }
            let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = data.withUnsafeBytes { buffer -> OSStatus in
                guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return OSStatus(paramErr) }
                return UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                      OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState, chars.count, &length, &chars)
            }
            if status == noErr, length > 0 { return String(utf16CodeUnits: chars, count: length) }
        }
        return nil
    }
}

extension Modifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var m: Modifiers = []
        if flags.contains(.control) { m.insert(.control) }
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.shift) { m.insert(.shift) }
        if flags.contains(.command) { m.insert(.command) }
        if flags.contains(.function) { m.insert(.function) }
        self = m
    }

    var eventFlags: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if contains(.control) { f.insert(.control) }
        if contains(.option) { f.insert(.option) }
        if contains(.shift) { f.insert(.shift) }
        if contains(.command) { f.insert(.command) }
        if contains(.function) { f.insert(.function) }
        return f
    }

    /// Carbon modifier mask for `RegisterEventHotKey`.
    var carbonFlags: UInt32 {
        var f: UInt32 = 0
        if contains(.control) { f |= UInt32(controlKey) }
        if contains(.option) { f |= UInt32(optionKey) }
        if contains(.shift) { f |= UInt32(shiftKey) }
        if contains(.command) { f |= UInt32(cmdKey) }
        return f
    }

    /// Quartz flags for synthesized `CGEvent`s.
    var cgEventFlags: CGEventFlags {
        var f: CGEventFlags = []
        if contains(.control) { f.insert(.maskControl) }
        if contains(.option) { f.insert(.maskAlternate) }
        if contains(.shift) { f.insert(.maskShift) }
        if contains(.command) { f.insert(.maskCommand) }
        if contains(.function) { f.insert(.maskSecondaryFn) }
        return f
    }
}
