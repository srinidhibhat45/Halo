import AppKit
import Observation

/// SF Symbols names, categories and search keywords, read at runtime from the system's
/// CoreGlyphs bundle. The plists are private and undocumented, so anything missing falls back
/// to a curated list.
nonisolated struct SymbolCatalog: Sendable {
    struct Category: Identifiable, Hashable, Sendable {
        var key: String
        var title: String
        var symbol: String
        var id: String { key }
    }

    /// Category keys, "all" first.
    var categories: [Category]
    /// Every symbol in SF Symbols order.
    var names: [String]
    var categoriesByName: [String: Set<String>]
    var keywordsByName: [String: [String]]

    /// Symbols in `category` ("all" for every symbol) whose name or keywords contain every word
    /// of `query`. Exact and prefix name matches come first.
    func symbols(in category: String, matching query: String) -> [String] {
        let pool = category == "all" ? names : names.filter { categoriesByName[$0]?.contains(category) == true }
        let terms = query.lowercased().split(whereSeparator: { $0 == " " || $0 == "." }).map(String.init)
        guard !terms.isEmpty else { return pool }
        let matches = pool.filter { name in
            let keywords = keywordsByName[name] ?? []
            return terms.allSatisfy { term in name.contains(term) || keywords.contains { $0.contains(term) } }
        }
        let needle = terms.joined(separator: ".")
        return matches.enumerated().sorted { a, b in
            let ra = Self.rank(a.element, needle), rb = Self.rank(b.element, needle)
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }

    private static func rank(_ name: String, _ needle: String) -> Int {
        if name == needle { return 0 }
        if name.hasPrefix(needle) { return 1 }
        return 2
    }

    // MARK: Loading

    private static let resources = URL(fileURLWithPath: "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources", isDirectory: true)

    /// Localised and right-to-left variants, which the picker hides.
    private static let variantSuffixes: Set<String> = [
        "ar", "hi", "rtl", "he", "ja", "th", "zh", "bn", "gu", "kn", "ko", "ml", "mni", "mr", "or", "pa", "sat", "te",
        "si", "ta", "el", "ru", "km", "my",
    ]

    /// Reads the system catalog (fast: no image loading). Falls back to `curated`.
    static func load() -> SymbolCatalog {
        guard let order = plist("symbol_order") as? [String], !order.isEmpty else { return curated }
        let released = releasedNames()
        let names = order.filter { name in
            guard let suffix = name.split(separator: ".").last.map(String.init), name.contains(".") else { return true }
            return !variantSuffixes.contains(suffix)
        }
        .filter { released?.contains($0) ?? true }

        let rawCategories = plist("symbol_categories") as? [String: [String]] ?? [:]
        let keywords = plist("symbol_search") as? [String: [String]] ?? [:]
        let categoryList = (plist("categories") as? [[String: String]] ?? []).compactMap { entry -> Category? in
            guard let key = entry["key"] else { return nil }
            return Category(key: key, title: title(forCategory: key), symbol: entry["icon"] ?? "square.grid.2x2")
        }
        return SymbolCatalog(
            categories: categoryList.contains { $0.key == "all" } ? categoryList : [allCategory] + categoryList,
            names: names,
            categoriesByName: rawCategories.mapValues(Set.init),
            keywordsByName: keywords.mapValues { $0.map { $0.lowercased() } }
        )
    }

    /// Drops names this system can't draw (checked with `NSImage(systemSymbolName:)`). Slow
    /// (about a second for every symbol); run off the main actor.
    func validated() -> SymbolCatalog {
        var copy = self
        copy.names = names.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }
        return copy
    }

    private static func plist(_ name: String) -> Any? {
        guard let data = try? Data(contentsOf: resources.appendingPathComponent(name + ".plist")) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil)
    }

    /// Names whose release (per name_availability.plist) is no newer than the running macOS,
    /// or nil if the file can't be read.
    private static func releasedNames() -> Set<String>? {
        guard let root = plist("name_availability") as? [String: Any],
              let symbols = root["symbols"] as? [String: String],
              let years = root["year_to_release"] as? [String: [String: String]] else { return nil }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let current = (os.majorVersion, os.minorVersion)
        let releasedYears = Set(years.compactMap { year, platforms -> String? in
            guard let macOS = platforms["macOS"] else { return nil }
            let parts = macOS.split(separator: ".").compactMap { Int($0) }
            let version = (parts.first ?? 0, parts.dropFirst().first ?? 0)
            return version <= current ? year : nil
        })
        return Set(symbols.compactMap { name, year in releasedYears.contains(year) ? name : nil })
    }

    private static let allCategory = Category(key: "all", title: "All", symbol: "square.grid.2x2")

    private static func title(forCategory key: String) -> String {
        let titles = [
            "all": "All", "whatsnew": "What's New", "draw": "Draw", "variable": "Variable", "multicolor": "Multicolor",
            "communication": "Communication", "weather": "Weather", "maps": "Maps", "objectsandtools": "Objects & Tools",
            "devices": "Devices", "cameraandphotos": "Camera & Photos", "gaming": "Gaming", "connectivity": "Connectivity",
            "transportation": "Transportation", "automotive": "Automotive", "accessibility": "Accessibility",
            "privacyandsecurity": "Privacy & Security", "human": "Human", "home": "Home", "fitness": "Fitness",
            "nature": "Nature", "editing": "Editing", "textformatting": "Text Formatting", "media": "Media",
            "keyboard": "Keyboard", "commerce": "Commerce", "time": "Time", "health": "Health", "shapes": "Shapes",
            "arrows": "Arrows", "indices": "Indices", "math": "Math",
        ]
        return titles[key] ?? key.capitalized
    }

    /// Used when the system catalog can't be read.
    static let curated: SymbolCatalog = {
        let groups: [(Category, [String])] = [
            (Category(key: "apps", title: "Apps & Windows", symbol: "macwindow"), [
                "app", "app.badge", "macwindow", "rectangle.split.2x1", "rectangle.lefthalf.filled", "rectangle.righthalf.filled",
                "rectangle.inset.filled", "rectangle.3.group", "square.grid.2x2", "square.grid.3x3.fill", "dock.rectangle",
                "menubar.rectangle", "sidebar.left", "display", "display.2", "desktopcomputer", "laptopcomputer",
            ]),
            (Category(key: "media", title: "Media", symbol: "playpause"), [
                "play.fill", "pause.fill", "playpause.fill", "forward.fill", "backward.fill", "speaker.wave.3.fill",
                "speaker.slash.fill", "music.note", "headphones", "mic.fill", "video.fill", "camera.fill", "photo",
                "sun.max.fill", "moon.fill",
            ]),
            (Category(key: "editing", title: "Editing", symbol: "pencil"), [
                "pencil", "square.and.pencil", "doc.on.doc", "doc.on.clipboard", "scissors", "trash", "arrow.uturn.backward",
                "arrow.uturn.forward", "textformat", "text.cursor", "character.cursor.ibeam", "magnifyingglass", "paintbrush",
                "eyedropper", "crop", "wand.and.stars", "sparkles",
            ]),
            (Category(key: "communication", title: "Communication", symbol: "message"), [
                "message.fill", "bubble.left.and.bubble.right.fill", "envelope.fill", "paperplane.fill", "phone.fill",
                "person.fill", "person.2.fill", "bell.fill", "megaphone.fill", "at",
            ]),
            (Category(key: "objects", title: "Objects", symbol: "folder"), [
                "folder.fill", "doc.fill", "doc.text", "book.fill", "bookmark.fill", "calendar", "clock.fill", "alarm.fill",
                "lock.fill", "key.fill", "gearshape.fill", "wrench.and.screwdriver.fill", "hammer.fill", "lightbulb.fill",
                "globe", "house.fill", "cart.fill", "creditcard.fill", "gift.fill", "star.fill", "heart.fill", "flag.fill",
                "tag.fill", "bolt.fill", "flame.fill", "leaf.fill", "cloud.fill", "terminal.fill", "command",
            ]),
            (Category(key: "shapes", title: "Shapes & Arrows", symbol: "circle"), [
                "circle", "circle.fill", "square", "square.fill", "triangle.fill", "diamond.fill", "hexagon.fill",
                "checkmark.circle.fill", "xmark.circle.fill", "plus.circle.fill", "minus.circle.fill", "questionmark.circle.fill",
                "arrow.up", "arrow.down", "arrow.left", "arrow.right", "arrow.clockwise", "arrow.triangle.2.circlepath",
            ]),
        ]
        var byName: [String: Set<String>] = [:]
        for (category, names) in groups {
            for name in names { byName[name, default: []].insert(category.key) }
        }
        return SymbolCatalog(
            categories: [allCategory] + groups.map(\.0),
            names: groups.flatMap(\.1).filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil },
            categoriesByName: byName,
            keywordsByName: [:]
        )
    }()
}

/// The loaded symbol catalog, shared by every icon picker.
@Observable
final class SymbolLibrary {
    static let shared = SymbolLibrary()

    /// Nil until the first load finishes.
    private(set) var catalog: SymbolCatalog?
    @ObservationIgnored private var isLoading = false

    private init() {}

    /// Reads the catalog in the background, then re-checks every name against the system and
    /// publishes the validated list if anything was dropped.
    func loadIfNeeded() {
        guard catalog == nil, !isLoading else { return }
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let loaded = SymbolCatalog.load()
            await MainActor.run { self.catalog = loaded }
            let validated = loaded.validated()
            guard validated.names.count != loaded.names.count else { return }
            await MainActor.run {
                Log.app.info("Symbol picker: \(loaded.names.count - validated.names.count) names not drawable on this system")
                self.catalog = validated
            }
        }
    }
}
