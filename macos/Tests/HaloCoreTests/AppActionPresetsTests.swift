import AppKit
import Testing
@testable import HaloCore

@Suite("AppActionPresets")
struct AppActionPresetsTests {
    @Test("Preset ids are unique and every preset names its app and source")
    func wellFormed() {
        let ids = AppActionPresets.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        for preset in AppActionPresets.all {
            #expect(!preset.bundleIDs.isEmpty, "\(preset.id) has no bundle id")
            #expect(!preset.title.isEmpty, "\(preset.id) has no title")
            #expect(preset.source.hasPrefix("https://"), "\(preset.id) has no source")
        }
    }

    @Test("Every preset's key is one `keys(_:_:)` knows and has a modifier or is a function key")
    func keys() {
        for preset in AppActionPresets.all {
            #expect(AppActionPresets.isKnownKey(preset.combo.keyLabel), "\(preset.id): unknown key \(preset.combo.keyLabel)")
        }
    }

    @Test("Every preset's SF Symbol exists")
    func symbols() {
        let missing = Set(AppActionPresets.all.map(\.symbol)).filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }
        #expect(missing.isEmpty, "Missing SF Symbols: \(missing.sorted())")
    }

    @Test("Teams has the meeting controls")
    func teams() {
        let titles = AppActionPresets.presets(forBundleID: "com.microsoft.teams2").map(\.title)
        #expect(titles.contains("Mute / Unmute"))
        #expect(titles.contains("Raise / Lower Hand"))
    }

    @Test("Suggested slots take the app's presets in order, aimed at that app")
    func suggested() {
        let slots = AppActionPresets.suggestedSlots(forBundleID: "com.figma.Desktop", limit: 8)
        #expect(!slots.isEmpty && slots.count <= 8)
        for slot in slots {
            guard case .appShortcut(let shortcut)? = slot.action else { Issue.record("not an app shortcut"); continue }
            #expect(shortcut.bundleID == "com.figma.Desktop")
        }
        #expect(AppActionPresets.suggestedSlots(forBundleID: "com.example.unknown").isEmpty)
    }
}
