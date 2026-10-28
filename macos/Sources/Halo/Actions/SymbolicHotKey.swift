import AppKit
import HaloCore

/// System keyboard shortcuts from Keyboard Settings (`com.apple.symbolichotkeys`), so actions that
/// go through a system shortcut honour the user's rebinding or switch-off.
///
/// IDs and defaults come from Keyboard Settings' DefaultShortcutsTable.xml (macOS 27.2).
enum SymbolicHotKey: Int {
    case saveScreen = 28
    case copyScreen = 29
    case saveArea = 30
    case copyArea = 31
    case spotlight = 64
    case notificationCenter = 163
    case doNotDisturb = 175

    struct Binding: Equatable {
        var keyCode: CGKeyCode
        var modifiers: CGEventFlags
    }

    /// The shortcut as currently set, or nil when it is turned off, unassigned (the default for
    /// Notification Center and Do Not Disturb) or needs the Globe key, which can't be synthesized.
    var binding: Binding? {
        guard let entry = Self.userEntries()[String(rawValue)] as? [String: Any] else { return defaultBinding }
        if let enabled = entry["enabled"] as? Bool, !enabled { return nil }
        guard let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [Int], parameters.count >= 3 else { return defaultBinding }
        // parameters = [character or 65535, virtual key code or 65535, NSEvent modifier mask]
        return Self.binding(keyCode: parameters[1], modifierMask: parameters[2])
    }

    private var defaultBinding: Binding? {
        switch self {
        case .saveScreen: Binding(keyCode: CGKeyCode(KeyCode.three), modifiers: [.maskShift, .maskCommand])
        case .copyScreen: Binding(keyCode: CGKeyCode(KeyCode.three), modifiers: [.maskControl, .maskShift, .maskCommand])
        case .saveArea: Binding(keyCode: CGKeyCode(KeyCode.four), modifiers: [.maskShift, .maskCommand])
        case .copyArea: Binding(keyCode: CGKeyCode(KeyCode.four), modifiers: [.maskControl, .maskShift, .maskCommand])
        case .spotlight: Binding(keyCode: CGKeyCode(KeyCode.space), modifiers: .maskCommand)
        case .notificationCenter, .doNotDisturb: nil
        }
    }

    private static func binding(keyCode: Int, modifierMask: Int) -> Binding? {
        guard (0..<0xFFFF).contains(keyCode), modifierMask >= 0 else { return nil }
        let code = CGKeyCode(keyCode)
        // NSEvent and Quartz share the device-independent modifier bits.
        let flags = CGEventFlags(rawValue: UInt64(modifierMask))
        // Function, arrow and navigation keys always carry the Fn bit; anywhere else it means Globe.
        if flags.contains(.maskSecondaryFn), !fnKeys.contains(code) { return nil }
        return Binding(keyCode: code, modifiers: flags.intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand]))
    }

    /// F1–F20, arrows, Home/End/Page Up/Page Down, Forward Delete and Help.
    private static let fnKeys: Set<CGKeyCode> = Set(
        [KeyCode.f1, KeyCode.f2, KeyCode.f3, KeyCode.f4, KeyCode.f5, KeyCode.f6, KeyCode.f7, KeyCode.f8, KeyCode.f9,
         KeyCode.f10, KeyCode.f11, KeyCode.f12, KeyCode.f13, KeyCode.f14, KeyCode.f15, KeyCode.f16, KeyCode.f17,
         KeyCode.f18, KeyCode.f19, KeyCode.f20, KeyCode.leftArrow, KeyCode.rightArrow, KeyCode.upArrow,
         KeyCode.downArrow, KeyCode.forwardDelete, 0x72, 0x73, 0x74, 0x77, 0x79].map { CGKeyCode($0) }
    )

    /// The user's overrides; IDs missing here use the system default.
    private static func userEntries() -> [String: Any] {
        let domain = "com.apple.symbolichotkeys" as CFString
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any] ?? [:]
    }
}

extension KeySender {
    /// Presses a system shortcut's current binding.
    @discardableResult
    static func press(_ binding: SymbolicHotKey.Binding) async -> Bool {
        await press(binding.keyCode, modifiers: binding.modifiers)
    }
}
