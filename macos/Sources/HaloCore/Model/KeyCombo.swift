import Foundation

/// Modifier keys, stored layout-independently.
public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let control  = Modifiers(rawValue: 1 << 0)
    public static let option   = Modifiers(rawValue: 1 << 1)
    public static let shift    = Modifiers(rawValue: 1 << 2)
    public static let command  = Modifiers(rawValue: 1 << 3)
    public static let function = Modifiers(rawValue: 1 << 4)

    /// Symbols in Apple's canonical order: ⌃ ⌥ ⇧ ⌘ (fn first when present).
    public var symbols: String {
        var s = ""
        if contains(.function) { s += "fn " }
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }

    /// Spoken/accessible names, e.g. "Control Option Command".
    public var names: [String] {
        var n: [String] = []
        if contains(.function) { n.append("Function") }
        if contains(.control) { n.append("Control") }
        if contains(.option) { n.append("Option") }
        if contains(.shift) { n.append("Shift") }
        if contains(.command) { n.append("Command") }
        return n
    }
}

/// A key plus modifiers, identified by its virtual key code (kVK_*), so it survives layout changes.
/// `keyLabel` caches what the key showed when it was recorded (e.g. "H", "Space", "F5") for display.
public struct KeyCombo: Codable, Hashable, Sendable {
    public var keyCode: UInt16
    public var modifiers: Modifiers
    public var keyLabel: String

    public init(keyCode: UInt16, modifiers: Modifiers, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    /// e.g. "⌃⌥⌘H"
    public var displayString: String { modifiers.symbols + keyLabel }

    /// e.g. "Control Option Command H"
    public var accessibilityLabel: String { (modifiers.names + [keyLabel]).joined(separator: " ") }

    /// Default ring trigger: ⌃⇧⌘H ("H" for Halo). Unused by macOS and easy to assign to a mouse button.
    public static let defaultTrigger = KeyCombo(keyCode: KeyCode.h, modifiers: [.control, .shift, .command], keyLabel: "H")
}

/// Virtual key codes (ANSI positions) used by defaults, presets and tests. Mirrors Carbon's kVK_* values.
public enum KeyCode {
    public static let a: UInt16 = 0x00
    public static let s: UInt16 = 0x01
    public static let d: UInt16 = 0x02
    public static let f: UInt16 = 0x03
    public static let h: UInt16 = 0x04
    public static let g: UInt16 = 0x05
    public static let z: UInt16 = 0x06
    public static let x: UInt16 = 0x07
    public static let c: UInt16 = 0x08
    public static let v: UInt16 = 0x09
    public static let b: UInt16 = 0x0B
    public static let q: UInt16 = 0x0C
    public static let w: UInt16 = 0x0D
    public static let e: UInt16 = 0x0E
    public static let r: UInt16 = 0x0F
    public static let y: UInt16 = 0x10
    public static let t: UInt16 = 0x11
    public static let one: UInt16 = 0x12
    public static let two: UInt16 = 0x13
    public static let three: UInt16 = 0x14
    public static let four: UInt16 = 0x15
    public static let six: UInt16 = 0x16
    public static let five: UInt16 = 0x17
    public static let nine: UInt16 = 0x19
    public static let seven: UInt16 = 0x1A
    public static let eight: UInt16 = 0x1C
    public static let zero: UInt16 = 0x1D
    public static let o: UInt16 = 0x1F
    public static let u: UInt16 = 0x20
    public static let i: UInt16 = 0x22
    public static let p: UInt16 = 0x23
    public static let l: UInt16 = 0x25
    public static let j: UInt16 = 0x26
    public static let k: UInt16 = 0x28
    public static let n: UInt16 = 0x2D
    public static let m: UInt16 = 0x2E
    public static let `return`: UInt16 = 0x24
    public static let tab: UInt16 = 0x30
    public static let space: UInt16 = 0x31
    public static let delete: UInt16 = 0x33
    public static let escape: UInt16 = 0x35
    public static let forwardDelete: UInt16 = 0x75
    public static let leftArrow: UInt16 = 0x7B
    public static let rightArrow: UInt16 = 0x7C
    public static let downArrow: UInt16 = 0x7D
    public static let upArrow: UInt16 = 0x7E
    public static let f1: UInt16 = 0x7A
    public static let f2: UInt16 = 0x78
    public static let f3: UInt16 = 0x63
    public static let f4: UInt16 = 0x76
    public static let f5: UInt16 = 0x60
    public static let f6: UInt16 = 0x61
    public static let f7: UInt16 = 0x62
    public static let f8: UInt16 = 0x64
    public static let f9: UInt16 = 0x65
    public static let f10: UInt16 = 0x6D
    public static let f11: UInt16 = 0x67
    public static let f12: UInt16 = 0x6F
    public static let f13: UInt16 = 0x69
    public static let f14: UInt16 = 0x6B
    public static let f15: UInt16 = 0x71
    public static let f16: UInt16 = 0x6A
    public static let f17: UInt16 = 0x40
    public static let f18: UInt16 = 0x4F
    public static let f19: UInt16 = 0x50
    public static let f20: UInt16 = 0x5A

    /// Digit row key codes for 1...9 then 0, used for "press a number to pick a slot".
    public static let digitRow: [UInt16] = [one, two, three, four, five, six, seven, eight, nine, zero]

    /// Human label for keys whose label does not come from the keyboard layout.
    public static func specialLabel(for code: UInt16) -> String? {
        switch code {
        case `return`: return "↩"
        case tab: return "⇥"
        case space: return "Space"
        case delete: return "⌫"
        case escape: return "⎋"
        case forwardDelete: return "⌦"
        case leftArrow: return "←"
        case rightArrow: return "→"
        case downArrow: return "↓"
        case upArrow: return "↑"
        case 0x73: return "↖"   // Home
        case 0x77: return "↘"   // End
        case 0x74: return "⇞"   // Page Up
        case 0x79: return "⇟"   // Page Down
        case f1: return "F1"
        case f2: return "F2"
        case f3: return "F3"
        case f4: return "F4"
        case f5: return "F5"
        case f6: return "F6"
        case f7: return "F7"
        case f8: return "F8"
        case f9: return "F9"
        case f10: return "F10"
        case f11: return "F11"
        case f12: return "F12"
        case f13: return "F13"
        case f14: return "F14"
        case f15: return "F15"
        case f16: return "F16"
        case f17: return "F17"
        case f18: return "F18"
        case f19: return "F19"
        case f20: return "F20"
        default: return nil
        }
    }
}
