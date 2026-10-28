import Foundation

/// A ready-made in-app action: one app's documented keyboard shortcut, e.g. Teams' Mute.
public struct AppActionPreset: Identifiable, Hashable, Sendable {
    /// Stable id, e.g. "teams.mute".
    public var id: String
    public var appName: String
    /// The app's bundle identifiers, newest first (apps sometimes ship under a new identifier).
    public var bundleIDs: [String]
    public var title: String
    public var symbol: String
    public var combo: KeyCombo
    /// Meeting controls default to "bring forward, send, return", so they work from any app.
    public var delivery: AppDelivery
    /// Where the shortcut is documented.
    public var source: String

    public init(id: String, appName: String, bundleIDs: [String], title: String, symbol: String, combo: KeyCombo,
                delivery: AppDelivery = .bringToFront, source: String) {
        self.id = id
        self.appName = appName
        self.bundleIDs = bundleIDs
        self.title = title
        self.symbol = symbol
        self.combo = combo
        self.delivery = delivery
        self.source = source
    }

    /// The action for this preset, aimed at `bundleID` (pick the installed variant) or the first.
    public func action(bundleID: String? = nil) -> Action {
        .appShortcut(AppShortcut(bundleID: bundleID ?? bundleIDs.first ?? "", appName: appName, title: title,
                                 combo: combo, symbol: symbol, delivery: delivery))
    }

    /// The library/picker entry.
    public var template: ActionTemplate {
        ActionTemplate(id: "preset.\(id)", category: .inApp, title: title,
                       subtitle: "\(appName) · \(combo.displayString)", symbol: symbol,
                       action: action(), keywords: [appName, "in-app", "app action"] + bundleIDs)
    }
}

/// Curated in-app shortcuts for popular apps, from each app's own documentation.
public enum AppActionPresets {
    public static let all: [AppActionPreset] = catalog

    /// Presets for the app with `bundleID`.
    public static func presets(forBundleID bundleID: String) -> [AppActionPreset] {
        all.filter { $0.bundleIDs.contains(bundleID) }
    }

    /// Slots holding the app's presets, in the catalogue's order (most useful first), at most
    /// `limit`, aimed at `bundleID`. Empty when Halo knows no actions for the app.
    public static func suggestedSlots(forBundleID bundleID: String, limit: Int = Ring.defaultSlotCount) -> [Slot] {
        presets(forBundleID: bundleID).prefix(max(0, limit)).map { preset in
            Slot(action: preset.action(bundleID: bundleID))
        }
    }

    /// Apps that have presets, by name, with their bundle identifiers.
    public static var apps: [(name: String, bundleIDs: [String])] {
        var seen = Set<String>()
        return all.compactMap { preset in
            seen.insert(preset.appName).inserted ? (preset.appName, preset.bundleIDs) : nil
        }
    }
}

public extension AppActionPresets {
    /// A combo from a key's label on a US keyboard ("M", "1", "Space", "←", "F5", ",", "Esc")
    /// and modifiers, for writing presets readably. Unknown labels map to Space so a typo is
    /// caught by `AppActionPresetsTests`.
    static func keys(_ label: String, _ modifiers: Modifiers) -> KeyCombo {
        KeyCombo(keyCode: ansiKeyCodes[label.uppercased()] ?? KeyCode.space, modifiers: modifiers, keyLabel: label.count == 1 ? label.uppercased() : label)
    }

    /// Whether `keys(_:_:)` knows the label.
    static func isKnownKey(_ label: String) -> Bool { ansiKeyCodes[label.uppercased()] != nil }

    private static let ansiKeyCodes: [String: UInt16] = [
        "A": 0x00, "S": 0x01, "D": 0x02, "F": 0x03, "H": 0x04, "G": 0x05, "Z": 0x06, "X": 0x07, "C": 0x08, "V": 0x09,
        "B": 0x0B, "Q": 0x0C, "W": 0x0D, "E": 0x0E, "R": 0x0F, "Y": 0x10, "T": 0x11, "1": 0x12, "2": 0x13, "3": 0x14,
        "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18, "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E,
        "O": 0x1F, "U": 0x20, "[": 0x21, "I": 0x22, "P": 0x23, "L": 0x25, "J": 0x26, "'": 0x27, "K": 0x28, ";": 0x29,
        "\\": 0x2A, ",": 0x2B, "/": 0x2C, "N": 0x2D, "M": 0x2E, ".": 0x2F, "`": 0x32,
        "RETURN": 0x24, "↩": 0x24, "TAB": 0x30, "SPACE": 0x31, "DELETE": 0x33, "ESC": 0x35, "ESCAPE": 0x35,
        "←": 0x7B, "→": 0x7C, "↓": 0x7D, "↑": 0x7E, "LEFT": 0x7B, "RIGHT": 0x7C, "DOWN": 0x7D, "UP": 0x7E,
        "F1": 0x7A, "F2": 0x78, "F3": 0x63, "F4": 0x76, "F5": 0x60, "F6": 0x61, "F7": 0x62, "F8": 0x64,
        "F9": 0x65, "F10": 0x6D, "F11": 0x67, "F12": 0x6F,
    ]
}
