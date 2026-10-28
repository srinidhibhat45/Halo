import AppKit
import Foundation
import Testing
@testable import HaloCore

@Suite("Config")
struct ConfigTests {
    @Test("Default config round-trips through JSON")
    func roundTrip() throws {
        var config = HaloConfig.default
        config.appProfiles.append(AppProfile(bundleID: "com.apple.Safari", appName: "Safari", ring: DefaultRings.media()))
        config.settings.trigger = nil
        let data = try ConfigFile.encode(config)
        let decoded = try ConfigFile.decode(data)
        #expect(decoded == config)
        #expect(decoded.settings.trigger == nil)
    }

    @Test("Every action kind round-trips")
    func everyAction() throws {
        let actions: [Action] = [
            .app(AppTarget(bundleID: "com.apple.Safari", name: "Safari", path: "/Applications/Safari.app", behavior: .toggle)),
            .url(WebLink(url: "https://example.com", openWithBundleID: "com.apple.Safari")),
            .file(FileTarget(path: "~/Downloads", revealInFinder: true)),
            .keystroke(KeyCombo(keyCode: KeyCode.t, modifiers: [.command, .shift], keyLabel: "T")),
            .media(.volumeUp),
            .screenshot(ScreenshotOptions(mode: .window, toClipboard: true)),
            .system(.lockScreen),
            .edit(.paste),
            .window(.leftHalf),
            .shortcut(ShortcutRef(name: "Morning", passSelection: true)),
            .appShortcut(AppShortcut(bundleID: "com.microsoft.teams2", appName: "Microsoft Teams", title: "Mute",
                                     combo: KeyCombo(keyCode: KeyCode.m, modifiers: [.shift, .command], keyLabel: "M"),
                                     symbol: "mic.slash", delivery: .bringToFrontAndReturn)),
            .menuItem(MenuItemRef(bundleID: "com.apple.Safari", appName: "Safari", path: ["View", "Show Sidebar"])),
            .clickButtons(ButtonSequence(bundleID: "com.microsoft.teams2", appName: "Microsoft Teams", title: "Start Recording",
                                         steps: [ButtonStep(names: ["More actions"]), ButtonStep(names: ["Confirm"], isOptional: true)])),
            .appleScript(ScriptSource(source: "beep")),
            .shell(ScriptSource(source: "say hi", shell: "/bin/zsh")),
            .text(TextSnippet(text: "Hello {date}", method: .type, pressReturn: true)),
            .aiPrompt(AIPrompt(service: .custom, template: "Explain {selection}", customURLTemplate: "https://x.test/?q={prompt}")),
            .folder(DefaultRings.windows()),
            .macro(Macro(steps: [MacroStep(action: .edit(.copy)), MacroStep(action: .media(.mute), delayAfter: 0.5)])),
        ]
        #expect(Set(actions.map(\.kind)) == Set(Action.Kind.allCases))
        for action in actions {
            let data = try JSONEncoder().encode(action)
            #expect(try JSONDecoder().decode(Action.self, from: data) == action)
        }
    }

    @Test("An unknown action type empties that slot instead of failing the config")
    func tolerantSlots() throws {
        let json = """
        {"globalRing":{"slots":[
          {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","action":{"type":"teleport","value":{}}},
          {"id":"7F9619FF-8B86-D011-B42D-00C04FC964FF","action":{"type":"media","value":"mute"}}
        ]}}
        """
        let config = try ConfigFile.decode(Data(json.utf8))
        #expect(config.globalRing.slotCount == Ring.slotRange.lowerBound)   // padded to the minimum
        #expect(config.globalRing[0].action == nil)
        #expect(config.globalRing[1].action == .media(.mute))
        #expect(config.settings == AppSettings())
    }

    @Test("Missing settings keys fall back to defaults; explicit null clears the trigger")
    func tolerantSettings() throws {
        let partial = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"theme":"glass","ringScale":9}"#.utf8))
        #expect(partial.theme == .glass)
        #expect(partial.ringScale == AppSettings.ringScaleRange.upperBound)
        #expect(partial.trigger == .defaultTrigger)
        let cleared = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"trigger":null}"#.utf8))
        #expect(cleared.trigger == nil)
    }

    @Test("Default trigger is Control-Shift-Command-H")
    func defaultTrigger() {
        #expect(KeyCombo.defaultTrigger.displayString == "⌃⇧⌘H")
        #expect(AppSettings().trigger == .defaultTrigger)
    }

    @Test("Ring resizing keeps filled slots")
    func resize() {
        var ring = Ring(slots: [Slot(action: .media(.mute)), Slot(), Slot(action: .edit(.copy)), Slot(), Slot(), Slot()])
        ring.resize(to: 4)
        #expect(ring.slotCount == 4)
        #expect(ring.filledCount == 2)
        ring.resize(to: 40)
        #expect(ring.slotCount == Ring.slotRange.upperBound)
        ring.resize(to: 1)
        #expect(ring.slotCount == Ring.slotRange.lowerBound)
    }

    @Test("Compacting keeps filled slots in order and maps them back")
    func compacting() {
        var ring = Ring(slotCount: 8)
        ring[1] = Slot(action: .media(.mute))
        ring[4] = Slot(action: .edit(.copy))
        ring[6] = Slot(action: .system(.lockScreen))
        let compact = ring.compacted()
        #expect(compact.ring.slotCount == 3)
        #expect(compact.sourceIndices == [1, 4, 6])
        #expect(compact.ring[1].action == .edit(.copy))
        #expect(RingGeometry(slotCount: 3).slot(dx: 0, dy: -100, deadZone: 10) == 0)

        let full = DefaultRings.media().compacted()
        #expect(full.sourceIndices == Array(0..<6))
        let empty = Ring(slotCount: 5).compacted()
        #expect(empty.ring.slotCount == 5)
    }

    @Test("Folder paths read and update nested rings")
    func folderPaths() {
        var ring = DefaultRings.global()
        let folderIndex = ring.slots.firstIndex { $0.action?.isFolder == true }!
        #expect(ring.ring(at: [folderIndex])?.slotCount == 6)
        #expect(ring.ring(at: [0]) == nil)
        let ok = ring.updateRing(at: [folderIndex]) { $0.clear(0) }
        #expect(ok)
        #expect(ring.ring(at: [folderIndex])?[0].action == nil)
    }

    @Test("App rings resolve, inherit empty slots, and respect the switch")
    func resolution() {
        var config = HaloConfig.default
        var appRing = Ring(slotCount: 8)
        appRing[0] = Slot(action: .edit(.copy))
        config.appProfiles = [AppProfile(bundleID: "com.example.app", appName: "Example", ring: appRing, inheritsGlobalSlots: true)]

        let resolved = config.resolvedRing(forFrontmostBundleID: "com.example.app")
        #expect(resolved.profile?.bundleID == "com.example.app")
        #expect(resolved.ring[0].action == .edit(.copy))
        #expect(resolved.ring[1].action == config.globalRing[1].action)
        #expect(Set(resolved.ring.slots.map(\.id)).count == resolved.ring.slotCount)

        #expect(config.resolvedRing(forFrontmostBundleID: "com.other").profile == nil)
        config.settings.appRingsEnabled = false
        #expect(config.resolvedRing(forFrontmostBundleID: "com.example.app").profile == nil)
    }

    @Test("Save rotates a backup and load recovers from a corrupt file")
    func disk() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "halo-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "config.json")

        #expect(ConfigFile.load(from: url).1 == .createdDefault)
        var config = HaloConfig.default
        try ConfigFile.save(config, to: url)
        config.settings.theme = .glass
        try ConfigFile.save(config, to: url)
        #expect(FileManager.default.fileExists(atPath: ConfigFile.backupURL(for: url).path))
        #expect(ConfigFile.load(from: url).0.settings.theme == .glass)

        try Data("{ not json".utf8).write(to: url)
        let (recovered, outcome) = ConfigFile.load(from: url)
        guard case .recoveredFromCorruption(let aside) = outcome else {
            Issue.record("expected recovery, got \(outcome)")
            return
        }
        #expect(FileManager.default.fileExists(atPath: aside.path))
        #expect(recovered.settings.theme == .classic)   // the backup is one edit behind
    }
}

@Suite("Catalog")
struct CatalogTests {
    @Test("Template ids are unique")
    func uniqueIDs() {
        let ids = ActionCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Every category has templates")
    func categoriesCovered() {
        for category in ActionCategory.allCases {
            #expect(!ActionCatalog.templates(in: category).isEmpty, "\(category) is empty")
        }
    }

    @Test("Search matches titles and keywords, all terms required")
    func search() {
        #expect(ActionCatalog.search("snip").contains { $0.id == "shot.area" })
        #expect(ActionCatalog.search("mute").contains { $0.id == "media.mute" })
        #expect(ActionCatalog.search("copy area").map(\.id) == ["shot.area.clip"])
        #expect(ActionCatalog.search("").count == ActionCatalog.all.count)
    }

    @Test("Every SF Symbol name used by the catalog exists on this macOS")
    func symbolsExist() {
        var names = Set(ActionCatalog.all.map(\.symbol))
        names.formUnion(ActionCategory.allCases.map(\.symbol))
        names.formUnion(MediaCommand.allCases.map(\.symbol))
        names.formUnion(SystemCommand.allCases.map(\.symbol))
        names.formUnion(EditCommand.allCases.map(\.symbol))
        names.formUnion(WindowCommand.allCases.map(\.symbol))
        names.formUnion(ScreenshotOptions.Mode.allCases.map { ScreenshotOptions(mode: $0).symbol })
        names.formUnion(Action.Kind.allCases.compactMap(sampleAction).map(\.defaultSymbol))
        let missing = names.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }.sorted()
        #expect(missing.isEmpty, "Missing SF Symbols: \(missing)")
    }

    @Test("Every icon in the default rings exists")
    func defaultRingSymbols() {
        func symbols(in ring: Ring) -> [String] {
            ring.slots.flatMap { slot -> [String] in
                var names: [String] = []
                if case .symbol(let name) = slot.displayIcon { names.append(name) }
                if case .folder(let inner) = slot.action { names += symbols(in: inner) }
                return names
            }
        }
        let names = Set(symbols(in: DefaultRings.global()) + symbols(in: DefaultRings.media()) + symbols(in: DefaultRings.ai()))
        let missing = names.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }.sorted()
        #expect(missing.isEmpty, "Missing SF Symbols: \(missing)")
    }

    private func sampleAction(_ kind: Action.Kind) -> Action? {
        ActionCatalog.all.first { $0.action.kind == kind }?.action
    }
}
