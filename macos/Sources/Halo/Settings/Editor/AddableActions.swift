import AppKit
import HaloCore

/// The groups of things that can go in a slot, in the order the Add to Ring picker and the
/// library list them.
enum AddableGroup: String, CaseIterable, Identifiable {
    case apps
    /// The library lists installed apps apart from the suggestions; the picker keeps them
    /// all under Apps.
    case installedApps
    /// Apps' own actions (presets such as Teams' Mute, any app shortcut or menu command).
    case inApp
    case media, screenshots, system, edit, windows, websites, files, keyboard
    case shortcuts, scripts, text, ai, nested, smart

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apps: "Apps"
        case .installedApps: "All Apps"
        case .inApp: "In-App Actions"
        case .media: "Media"
        case .screenshots: "Screenshots"
        case .system: "System"
        case .edit: "Edit"
        case .windows: "Windows"
        case .websites: "Websites"
        case .files: "Files & Folders"
        case .keyboard: "Keyboard Shortcut"
        case .shortcuts: "Apple Shortcuts"
        case .scripts: "Scripts"
        case .text: "Text Snippets"
        case .ai: "AI Prompts"
        case .nested: "Nested Rings"
        case .smart: "Smart Actions"
        }
    }

    /// The catalog category whose templates this group lists.
    var category: ActionCategory {
        switch self {
        case .apps, .installedApps: .apps
        case .inApp: .inApp
        case .media: .media
        case .screenshots: .screenshots
        case .system: .system
        case .edit: .edit
        case .windows: .window
        case .websites: .web
        case .files: .files
        case .keyboard: .keyboard
        case .shortcuts: .shortcuts
        case .scripts: .scripts
        case .text: .text
        case .ai: .ai
        case .nested: .folders
        case .smart: .macros
        }
    }

    var symbol: String {
        switch self {
        case .apps: "clock"
        case .installedApps: "square.grid.3x3"
        default: category.symbol
        }
    }

    /// Extra words that find the whole group.
    var searchTerms: [String] {
        switch self {
        case .apps, .installedApps: ["application", "launch", "open"]
        case .websites: ["web", "website", "link", "url", "browser", "site", "address"]
        case .files: ["file", "folder", "finder", "document"]
        case .shortcuts: ["shortcuts", "automation", "workflow"]
        case .keyboard: ["keys", "hotkey", "keystroke", "press"]
        case .nested: ["folder", "group", "submenu", "ring"]
        case .inApp: ["in-app", "app action", "meeting", "call", "menu", "command"]
        case .smart: ["macro", "sequence", "steps"]
        default: []
        }
    }

    /// Columns in the picker: app icons in a wide grid, the website entry full width, other
    /// actions in two columns of tiles.
    var pickerColumns: Int {
        switch self {
        case .apps, .installedApps: 6
        case .websites: 1
        default: 2
        }
    }

    /// How many items the picker shows before "Show All", or nil for all of them.
    var pickerPreviewLimit: Int? {
        switch self {
        case .apps: 17
        case .shortcuts: 6
        case .inApp: 9
        default: nil
        }
    }
}

/// One thing that can go in a slot: an app, a catalog template, one of the user's shortcuts, a
/// web address, or an entry point that asks for something first (a file, another app).
struct AddableItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case app(AppInfo)
        case template(ActionTemplate)
        case shortcut(name: String)
        case website(address: String)
        /// The picker's "type a web address" row.
        case webEntry
        /// Opens a file panel.
        case chooseFile
        /// Opens a panel for an app that isn't listed.
        case chooseApp
    }

    var kind: Kind
    var id: String
    var title: String
    var subtitle: String
    var icon: IconSpec
    /// What search matches against.
    var searchText: String

    /// The slot this item fills, or nil for items that ask for something first.
    var slot: Slot? {
        switch kind {
        case .app(let app): app.editorSlot()
        case .template(let template): template.editorSlot()
        case .shortcut(let name): Slot(action: .shortcut(ShortcutRef(name: name)))
        case .website(let address): Slot(action: .url(WebLink(url: address)))
        case .webEntry, .chooseFile, .chooseApp: nil
        }
    }

    /// The slot still needs details (an address, keys, a script…), which the inspector asks for.
    var needsSetup: Bool {
        if case .template(let template) = kind { return template.needsSetup }
        return false
    }

    /// The library's drag payload, for items that can be dragged onto the ring.
    var dragToken: String? {
        switch kind {
        case .app(let app): EditorDragToken.app(app.bundleID)
        case .template(let template): EditorDragToken.template(template.id)
        case .shortcut(let name): EditorDragToken.shortcut(name)
        case .website, .webEntry, .chooseFile, .chooseApp: nil
        }
    }

    static func app(_ app: AppInfo) -> AddableItem {
        AddableItem(kind: .app(app), id: "app:" + app.bundleID, title: app.name, subtitle: "Opens \(app.name)",
                    icon: .app(bundleID: app.bundleID), searchText: app.name + " " + app.bundleID)
    }

    static func template(_ template: ActionTemplate, in group: AddableGroup) -> AddableItem {
        let title = switch template.id {
        case "url.custom": "Website or Link…"
        case "file.choose": "File or Folder…"
        default: template.title
        }
        let words = [title, template.subtitle, group.title] + group.searchTerms + template.keywords
        return AddableItem(kind: .template(template), id: "template:" + template.id, title: title, subtitle: template.subtitle,
                           icon: .symbol(name: template.symbol), searchText: words.joined(separator: " "))
    }

    static func shortcut(_ name: String) -> AddableItem {
        AddableItem(kind: .shortcut(name: name), id: "shortcut:" + name, title: name, subtitle: "Runs this shortcut",
                    icon: .symbol(name: "square.2.layers.3d.fill"), searchText: name + " shortcut")
    }

    static func website(_ address: String) -> AddableItem {
        let host = Action.url(WebLink(url: address)).defaultTitle
        return AddableItem(kind: .website(address: address), id: "website:" + address, title: "Open \(host)",
                           subtitle: address, icon: .symbol(name: "globe"), searchText: address)
    }

    static let webEntry = AddableItem(kind: .webEntry, id: "web-entry", title: "Web Address", subtitle: "Type an address, like apple.com",
                                      icon: .symbol(name: "globe"), searchText: "")

    static let chooseFile = AddableItem(kind: .chooseFile, id: "choose-file", title: "Choose File or Folder…",
                                        subtitle: "Opens anything on your Mac", icon: .symbol(name: "folder.badge.plus"),
                                        searchText: "choose file folder document open")

    static let chooseApp = AddableItem(kind: .chooseApp, id: "choose-app", title: "Other App…", subtitle: "Choose an app on your Mac",
                                       icon: .symbol(name: "folder"), searchText: "other app choose application")
}

/// A group with the items to show.
struct AddableSection: Identifiable {
    var group: AddableGroup
    var title: String
    var items: [AddableItem]
    /// Items left out until the section is expanded (picker only).
    var hiddenCount = 0

    var id: AddableGroup { group }
}

/// Builds the picker's and the library's sections from the catalog, the user's apps and their
/// shortcuts, filtered by a search.
struct AddableCatalog {
    enum Purpose {
        /// The Add to Ring popover: one click adds, with entry points that ask for a file or an
        /// address, and long groups trimmed until expanded.
        case picker
        /// The drag-and-drop library: only items that can be dragged onto the ring.
        case library
    }

    var purpose: Purpose
    /// Recently used, then running apps.
    var suggestedApps: [AppInfo]
    /// Every installed app, by name.
    var installedApps: [AppInfo]
    var shortcutNames: [String]
    /// The app whose ring is being edited, if it's an app ring: its actions are listed first.
    var ringApp: AppInfo?

    /// The catalog for the current Mac: recent apps first, then running ones, then the rest.
    init(purpose: Purpose, recentApps: [AppInfo], shortcutNames: [String], ringApp: AppInfo? = nil) {
        self.ringApp = ringApp
        let me = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        self.purpose = purpose
        self.suggestedApps = (recentApps + AppCatalog.shared.runningApps).filter { $0.bundleID != me && seen.insert($0.bundleID).inserted }
        self.installedApps = AppCatalog.shared.installed.filter { $0.bundleID != me && seen.insert($0.bundleID).inserted }
        self.shortcutNames = shortcutNames
    }

    /// The sections with items matching `query` (every item when it is empty).
    /// - Parameter expanded: picker groups shown in full rather than trimmed.
    func sections(matching query: String, expanded: Set<AddableGroup> = []) -> [AddableSection] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let terms = trimmed.split(separator: " ").map(String.init)
        // In an app's ring, that app's own actions come first.
        let groups = ringApp == nil ? AddableGroup.allCases : [.inApp] + AddableGroup.allCases.filter { $0 != .inApp }
        return groups.compactMap { group in
            var items = items(in: group, query: trimmed)
            if !terms.isEmpty {
                items = items.filter { item in
                    item.kind == .webEntry || terms.allSatisfy { item.searchText.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
                }
                if group.category == .apps { items = Self.prefixMatchesFirst(items, term: terms[0]) }
                // The address row alone is shown only when the search is about websites.
                if items.allSatisfy({ $0.kind == .webEntry }), !Self.matchesGroup(group, terms) { items = [] }
            }
            guard !items.isEmpty else { return nil }
            let title = if purpose == .library && group == .apps {
                "Suggested Apps"
            } else if group == .inApp, let ringApp, terms.isEmpty {
                "For \(ringApp.name)"
            } else {
                group.title
            }
            var section = AddableSection(group: group, title: title, items: items)
            if purpose == .picker, terms.isEmpty, !expanded.contains(group), let limit = previewLimit(for: group), items.count > limit + 1 {
                // Keep a trailing entry point ("Other App…") visible.
                let tail = items.last.flatMap { $0.kind == .chooseApp ? $0 : nil }
                let body = tail == nil ? items : Array(items.dropLast())
                section.items = Array(body.prefix(limit)) + (tail.map { [$0] } ?? [])
                section.hiddenCount = items.count - section.items.count
            }
            return section
        }
    }

    private func items(in group: AddableGroup, query: String) -> [AddableItem] {
        let templates = ActionCatalog.templates(in: group.category)
        switch group {
        case .apps:
            guard purpose == .picker else { return suggestedApps.map(AddableItem.app) }
            return (suggestedApps + installedApps).map(AddableItem.app) + [.chooseApp]
        case .installedApps:
            return purpose == .library ? installedApps.map(AddableItem.app) : []
        case .websites:
            guard purpose == .picker else { return templates.map { .template($0, in: group) } }
            // A search that is an address offers it directly; otherwise a row to type one.
            return [WebAddress.normalized(query).map(AddableItem.website) ?? .webEntry]
        case .files:
            guard purpose == .picker else { return templates.map { .template($0, in: group) } }
            return [.chooseFile] + templates.filter { !$0.needsSetup }.map { .template($0, in: group) }
        case .shortcuts:
            guard !shortcutNames.isEmpty else { return templates.map { .template($0, in: group) } }
            return shortcutNames.map(AddableItem.shortcut)
        case .inApp:
            return inAppItems()
        default:
            return templates.map { .template($0, in: group) }
        }
    }

    /// In an app's ring: that app's presets, then App Shortcut / Menu Command aimed at it, then
    /// presets for the other installed apps. Elsewhere: installed apps' presets, then the
    /// generic entries.
    private func inAppItems() -> [AddableItem] {
        func item(_ preset: AppActionPreset, aimedAt bundleID: String?) -> AddableItem {
            var template = preset.template
            template.action = preset.action(bundleID: bundleID)
            return .template(template, in: .inApp)
        }
        /// The installed variant a preset should target (Meet presets list every browser).
        func installedID(_ preset: AppActionPreset) -> String? {
            preset.bundleIDs.first { AppCatalog.shared.info(bundleID: $0) != nil }
        }
        let generic: [AddableItem] = ActionCatalog.inApp.map { template in
            var aimed = template
            if let ringApp {
                switch template.action {
                case .appShortcut(var shortcut):
                    shortcut.bundleID = ringApp.bundleID
                    shortcut.appName = ringApp.name
                    aimed.action = .appShortcut(shortcut)
                case .menuItem(var item):
                    item.bundleID = ringApp.bundleID
                    item.appName = ringApp.name
                    aimed.action = .menuItem(item)
                default:
                    break
                }
            }
            return .template(aimed, in: .inApp)
        }
        // Each preset once, in catalog order (grouped by app).
        let forRing = ringApp.map { app in AppActionPresets.all.filter { $0.bundleIDs.contains(app.bundleID) } } ?? []
        let ringIDs = Set(forRing.map(\.id))
        let others = AppActionPresets.all
            .filter { !ringIDs.contains($0.id) }
            .compactMap { preset in installedID(preset).map { item(preset, aimedAt: $0) } }
        guard let ringApp else { return others + generic }
        return forRing.map { item($0, aimedAt: ringApp.bundleID) } + generic + others
    }

    /// The picker shows all of an app ring's own actions (plus its two generic entries) before
    /// "Show All"; elsewhere the usual group limit.
    private func previewLimit(for group: AddableGroup) -> Int? {
        guard group == .inApp, let ringApp else { return group.pickerPreviewLimit }
        return max(AppActionPresets.presets(forBundleID: ringApp.bundleID).count + ActionCatalog.inApp.count, 2)
    }

    private static func matchesGroup(_ group: AddableGroup, _ terms: [String]) -> Bool {
        let words = ([group.title] + group.searchTerms).joined(separator: " ")
        return terms.allSatisfy { words.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// Apps whose name starts with the search first, keeping the order otherwise ("Other App…"
    /// stays last).
    private static func prefixMatchesFirst(_ items: [AddableItem], term: String) -> [AddableItem] {
        let apps = items.filter { $0.kind != .chooseApp }
        let starts = apps.filter { $0.title.range(of: term, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil }
        let rest = apps.filter { $0.title.range(of: term, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) == nil }
        return starts + rest + items.filter { $0.kind == .chooseApp }
    }
}

/// Turning typed text into a web address.
enum WebAddress {
    /// The address to open for `text`: as typed when it has a scheme ("https://…",
    /// "obsidian://…"), with https:// added for a bare domain ("apple.com"), nil otherwise.
    static func normalized(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        if trimmed.contains("://") { return URL(string: trimmed) == nil ? nil : trimmed }
        let host = trimmed.split(separator: "/").first.map(String.init) ?? trimmed
        let labels = host.split(separator: ".")
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }), let tld = labels.last, tld.count >= 2,
              tld.allSatisfy(\.isLetter) else { return nil }
        let address = "https://" + trimmed
        return URL(string: address) == nil ? nil : address
    }
}
