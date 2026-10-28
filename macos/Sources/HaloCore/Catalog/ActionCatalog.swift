import Foundation

/// A ready-made action shown in the configurator's library.
public struct ActionTemplate: Identifiable, Hashable, Sendable {
    public var id: String
    public var category: ActionCategory
    public var title: String
    public var subtitle: String
    public var symbol: String
    /// The action a slot gets when this template is dropped on it.
    public var action: Action
    /// The template is a starting point that needs details (pick an app, record keys, write a
    /// script…): the editor opens on drop.
    public var needsSetup: Bool
    /// Extra words matched by search.
    public var keywords: [String]

    public init(id: String, category: ActionCategory, title: String, subtitle: String, symbol: String, action: Action, needsSetup: Bool = false, keywords: [String] = []) {
        self.id = id
        self.category = category
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.action = action
        self.needsSetup = needsSetup
        self.keywords = keywords
    }
}

/// Every built-in template, grouped by category. Apps are listed dynamically by the app target
/// (installed/running apps); the "Choose App…" template here is the generic entry point.
public enum ActionCatalog {
    public static let all: [ActionTemplate] = apps + inApp + inAppPresets + web + files + media + screenshots + system
        + edit + window + keyboard + shortcuts + scripts + text + ai + folders + macros

    public static func templates(in category: ActionCategory) -> [ActionTemplate] {
        all.filter { $0.category == category }
    }

    public static func template(id: String) -> ActionTemplate? { all.first { $0.id == id } }

    /// Case- and diacritic-insensitive search over titles, subtitles, categories and keywords.
    public static func search(_ query: String) -> [ActionTemplate] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return all }
        let terms = q.split(separator: " ").map(String.init)
        return all.filter { t in
            let haystack = ([t.title, t.subtitle, t.category.title] + t.keywords).joined(separator: " ")
            return terms.allSatisfy { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    // MARK: Groups

    static let apps: [ActionTemplate] = [
        ActionTemplate(id: "app.choose", category: .apps, title: "Open App…", subtitle: "Launch or switch to an app", symbol: "app.badge",
                       action: .app(AppTarget(bundleID: "", name: "App")), needsSetup: true, keywords: ["launch", "application", "open"]),
        ActionTemplate(id: "app.toggle", category: .apps, title: "Toggle App…", subtitle: "Show the app, or hide it if it's in front", symbol: "app.connected.to.app.below.fill",
                       action: .app(AppTarget(bundleID: "", name: "App", behavior: .toggle)), needsSetup: true, keywords: ["hide", "show"]),
        ActionTemplate(id: "app.quit", category: .apps, title: "Quit App…", subtitle: "Quit a running app", symbol: "xmark.app",
                       action: .app(AppTarget(bundleID: "", name: "App", behavior: .quit)), needsSetup: true, keywords: ["close", "exit"]),
    ]

    /// The generic in-app entry points (presets come from `AppActionPresets`).
    public static let inApp: [ActionTemplate] = [
        ActionTemplate(id: "inapp.shortcut", category: .inApp, title: "App Shortcut…", subtitle: "A shortcut sent to one app, even from another app", symbol: "command.square",
                       action: .appShortcut(AppShortcut(bundleID: "", appName: "App", title: "", combo: KeyCombo(keyCode: KeyCode.m, modifiers: [.shift, .command], keyLabel: "M"))),
                       needsSetup: true, keywords: ["in-app", "app action", "plugin", "teams", "zoom", "meeting"]),
        ActionTemplate(id: "inapp.menu", category: .inApp, title: "Menu Command…", subtitle: "Any command from an app's menu bar", symbol: "filemenu.and.selection",
                       action: .menuItem(MenuItemRef(bundleID: "", appName: "App", path: [])),
                       needsSetup: true, keywords: ["menu bar", "menu item", "command", "in-app"]),
    ]

    static var inAppPresets: [ActionTemplate] { AppActionPresets.all.map(\.template) }

    static let web: [ActionTemplate] = [
        ActionTemplate(id: "url.custom", category: .web, title: "Open Website…", subtitle: "Any web page or app link", symbol: "globe",
                       action: .url(WebLink(url: "https://")), needsSetup: true, keywords: ["url", "link", "browser", "site", "deep link"]),
    ]

    static let files: [ActionTemplate] = [
        ActionTemplate(id: "file.choose", category: .files, title: "Open File or Folder…", subtitle: "Open anything in Finder's default app", symbol: "doc",
                       action: .file(FileTarget(path: "")), needsSetup: true, keywords: ["document", "path"]),
        ActionTemplate(id: "file.downloads", category: .files, title: "Downloads", subtitle: "Open your Downloads folder", symbol: "arrow.down.circle",
                       action: .file(FileTarget(path: "~/Downloads")), keywords: ["folder"]),
        ActionTemplate(id: "file.desktop", category: .files, title: "Desktop Folder", subtitle: "Open your Desktop folder", symbol: "menubar.dock.rectangle",
                       action: .file(FileTarget(path: "~/Desktop")), keywords: ["folder"]),
        ActionTemplate(id: "file.documents", category: .files, title: "Documents", subtitle: "Open your Documents folder", symbol: "doc.text",
                       action: .file(FileTarget(path: "~/Documents")), keywords: ["folder"]),
        ActionTemplate(id: "file.home", category: .files, title: "Home Folder", subtitle: "Open your home folder", symbol: "house",
                       action: .file(FileTarget(path: "~")), keywords: ["folder", "user"]),
    ]

    static let media: [ActionTemplate] = MediaCommand.allCases.map { m in
        ActionTemplate(id: "media.\(m.rawValue)", category: .media, title: m.title, subtitle: mediaSubtitle(m), symbol: m.symbol,
                       action: .media(m), keywords: ["music", "audio", "sound", "media key"])
    }

    static let screenshots: [ActionTemplate] = [
        ActionTemplate(id: "shot.area", category: .screenshots, title: "Screenshot Area", subtitle: "Drag to capture part of the screen", symbol: "rectangle.dashed",
                       action: .screenshot(ScreenshotOptions(mode: .area)), keywords: ["capture", "snip", "selection"]),
        ActionTemplate(id: "shot.area.clip", category: .screenshots, title: "Copy Area", subtitle: "Capture an area to the clipboard", symbol: "rectangle.dashed.and.paperclip",
                       action: .screenshot(ScreenshotOptions(mode: .area, toClipboard: true)), keywords: ["capture", "clipboard", "snip"]),
        ActionTemplate(id: "shot.window", category: .screenshots, title: "Screenshot Window", subtitle: "Click a window to capture it", symbol: "macwindow",
                       action: .screenshot(ScreenshotOptions(mode: .window)), keywords: ["capture"]),
        ActionTemplate(id: "shot.full", category: .screenshots, title: "Screenshot Screen", subtitle: "Capture the screen under the pointer", symbol: "display",
                       action: .screenshot(ScreenshotOptions(mode: .fullScreen)), keywords: ["capture", "full screen"]),
        ActionTemplate(id: "shot.toolbar", category: .screenshots, title: "Screenshot Tools", subtitle: "Open the screenshot and recording toolbar", symbol: "camera.viewfinder",
                       action: .screenshot(ScreenshotOptions(mode: .toolbar)), keywords: ["record", "video", "capture"]),
    ]

    static let system: [ActionTemplate] = SystemCommand.allCases.map { s in
        ActionTemplate(id: "system.\(s.rawValue)", category: .system, title: s.title, subtitle: systemSubtitle(s), symbol: s.symbol,
                       action: .system(s), keywords: ["mac", "os"])
    }

    static let edit: [ActionTemplate] = EditCommand.allCases.map { e in
        ActionTemplate(id: "edit.\(e.rawValue)", category: .edit, title: e.title, subtitle: "Sends \(e.keyCombo.displayString) to the front app", symbol: e.symbol,
                       action: .edit(e), keywords: ["clipboard", "text"])
    }

    static let window: [ActionTemplate] = WindowCommand.allCases.map { w in
        ActionTemplate(id: "window.\(w.rawValue)", category: .window, title: w.title, subtitle: windowSubtitle(w), symbol: w.symbol,
                       action: .window(w), keywords: ["window", "snap", "tile", "resize", "move"])
    }

    static let keyboard: [ActionTemplate] = [
        ActionTemplate(id: "keys.custom", category: .keyboard, title: "Keyboard Shortcut…", subtitle: "Press any key combination in the front app", symbol: "command",
                       action: .keystroke(KeyCombo(keyCode: KeyCode.c, modifiers: .command, keyLabel: "C")), needsSetup: true, keywords: ["hotkey", "keystroke", "keys"]),
    ]

    static let shortcuts: [ActionTemplate] = [
        ActionTemplate(id: "shortcut.run", category: .shortcuts, title: "Run Shortcut…", subtitle: "Run a shortcut from the Shortcuts app", symbol: "square.2.layers.3d.fill",
                       action: .shortcut(ShortcutRef(name: "")), needsSetup: true, keywords: ["automation", "workflow", "apple shortcuts"]),
    ]

    static let scripts: [ActionTemplate] = [
        ActionTemplate(id: "script.applescript", category: .scripts, title: "AppleScript…", subtitle: "Run an AppleScript", symbol: "applescript.fill",
                       action: .appleScript(ScriptSource(source: "display notification \"Hello from Halo\" with title \"Halo\"")), needsSetup: true, keywords: ["osascript", "automation"]),
        ActionTemplate(id: "script.shell", category: .scripts, title: "Shell Command…", subtitle: "Run a command in your login shell", symbol: "terminal.fill",
                       action: .shell(ScriptSource(source: "open ~/Downloads")), needsSetup: true, keywords: ["bash", "zsh", "terminal", "command line"]),
    ]

    static let text: [ActionTemplate] = [
        ActionTemplate(id: "text.custom", category: .text, title: "Text Snippet…", subtitle: "Paste saved text into the front app", symbol: "text.cursor",
                       action: .text(TextSnippet(text: "")), needsSetup: true, keywords: ["snippet", "type", "paste", "signature", "template"]),
        ActionTemplate(id: "text.date", category: .text, title: "Today's Date", subtitle: "Types the current date", symbol: "calendar",
                       action: .text(TextSnippet(text: "{date}")), keywords: ["snippet", "time"]),
    ]

    static let ai: [ActionTemplate] = [
        ActionTemplate(id: "ai.summarize", category: .ai, title: "Summarize", subtitle: "Summarize the selected text", symbol: "text.append",
                       action: .aiPrompt(AIPrompt(service: .claude, template: "Summarize this in a few bullet points:\n\n{selection}")), keywords: ["ai", "llm", "claude", "chatgpt"]),
        ActionTemplate(id: "ai.proofread", category: .ai, title: "Fix Writing", subtitle: "Fix grammar and spelling in the selection", symbol: "checkmark.seal",
                       action: .aiPrompt(AIPrompt(service: .claude, template: "Fix the grammar and spelling, keep my tone. Reply with the corrected text only:\n\n{selection}")), keywords: ["ai", "grammar", "proofread"]),
        ActionTemplate(id: "ai.explain", category: .ai, title: "Explain", subtitle: "Explain the selected text simply", symbol: "lightbulb",
                       action: .aiPrompt(AIPrompt(service: .claude, template: "Explain this simply:\n\n{selection}")), keywords: ["ai", "eli5"]),
        ActionTemplate(id: "ai.translate", category: .ai, title: "Translate", subtitle: "Translate the selection to English", symbol: "character.bubble",
                       action: .aiPrompt(AIPrompt(service: .claude, template: "Translate this to English:\n\n{selection}")), keywords: ["ai", "language"]),
        ActionTemplate(id: "ai.custom", category: .ai, title: "Custom Prompt…", subtitle: "Your own prompt for ChatGPT, Claude and others", symbol: "sparkles",
                       action: .aiPrompt(AIPrompt(service: .claude, template: "{selection}")), needsSetup: true, keywords: ["ai", "prompt builder"]),
    ]

    static let folders: [ActionTemplate] = [
        ActionTemplate(id: "folder.empty", category: .folders, title: "Nested Ring", subtitle: "A slot that opens another ring", symbol: "circle.grid.cross.fill",
                       action: .folder(Ring(slotCount: 6)), keywords: ["folder", "group", "submenu", "sub-ring"]),
        ActionTemplate(id: "folder.media", category: .folders, title: "Media Controls Ring", subtitle: "Play, skip, volume and mute", symbol: "music.note",
                       action: .folder(DefaultRings.media()), keywords: ["folder", "music"]),
        ActionTemplate(id: "folder.windows", category: .folders, title: "Window Layout Ring", subtitle: "Halves, fill, centre and displays", symbol: "rectangle.split.2x1",
                       action: .folder(DefaultRings.windows()), keywords: ["folder", "snap", "tile"]),
    ]

    static let macros: [ActionTemplate] = [
        ActionTemplate(id: "macro.custom", category: .macros, title: "Smart Action…", subtitle: "Chain several actions with delays", symbol: "wand.and.stars",
                       action: .macro(Macro()), needsSetup: true, keywords: ["macro", "sequence", "multi-step", "workflow"]),
    ]

    // MARK: Subtitles

    private static func mediaSubtitle(_ m: MediaCommand) -> String {
        switch m {
        case .playPause: "Play or pause what's playing"
        case .nextTrack: "Skip to the next track"
        case .previousTrack: "Go back a track"
        case .volumeUp: "Raise the volume"
        case .volumeDown: "Lower the volume"
        case .mute: "Mute or unmute sound"
        case .brightnessUp: "Brighten the display"
        case .brightnessDown: "Dim the display"
        }
    }

    private static func systemSubtitle(_ s: SystemCommand) -> String {
        switch s {
        case .missionControl: "See all open windows and Spaces"
        case .appExpose: "See the front app's windows"
        case .showDesktop: "Move windows aside"
        case .launchpad: "Browse all your apps"
        case .notificationCenter: "Open notifications and widgets"
        case .spotlight: "Search your Mac"
        case .siri: "Talk to Siri"
        case .lockScreen: "Lock your Mac"
        case .sleepDisplay: "Turn the display off"
        case .sleep: "Put the Mac to sleep"
        case .screenSaver: "Start the screen saver"
        case .emojiPicker: "Insert emoji and symbols"
        case .dictation: "Start dictation"
        case .toggleDarkMode: "Switch light and dark appearance"
        case .doNotDisturb: "Toggle Do Not Disturb"
        case .forceQuit: "Open the Force Quit window"
        case .systemSettings: "Open System Settings"
        }
    }

    private static func windowSubtitle(_ w: WindowCommand) -> String {
        switch w {
        case .leftHalf: "Move the front window to the left half"
        case .rightHalf: "Move the front window to the right half"
        case .topHalf: "Move the front window to the top half"
        case .bottomHalf: "Move the front window to the bottom half"
        case .maximize: "Fill the screen without full screen"
        case .center: "Center the front window"
        case .minimize: "Minimize the front window"
        case .toggleFullScreen: "Enter or leave full screen"
        case .nextDisplay: "Move the window to the next display"
        case .close: "Close the front window"
        }
    }
}
