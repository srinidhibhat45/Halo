import Foundation

/// What a ring slot does when chosen.
///
/// Encoded as `{"type": "<kind>", "value": {...payload}}` so configs stay readable and a single
/// unknown or broken action never invalidates a whole config (see `Slot`'s tolerant decoding).
public enum Action: Hashable, Sendable {
    case app(AppTarget)
    case url(WebLink)
    case file(FileTarget)
    case keystroke(KeyCombo)
    case media(MediaCommand)
    case screenshot(ScreenshotOptions)
    case system(SystemCommand)
    case edit(EditCommand)
    case window(WindowCommand)
    case shortcut(ShortcutRef)
    /// A keyboard shortcut meant for one app (e.g. Teams' Mute), optionally sent from anywhere.
    case appShortcut(AppShortcut)
    /// A command from an app's menu bar, chosen by its menu path.
    case menuItem(MenuItemRef)
    /// Buttons in an app's window, clicked in order by name (e.g. Teams: More actions › Record).
    case clickButtons(ButtonSequence)
    case appleScript(ScriptSource)
    case shell(ScriptSource)
    case text(TextSnippet)
    case aiPrompt(AIPrompt)
    /// A nested ring. The slot's title/icon name the folder.
    case folder(Ring)
    /// A multi-step "Smart Action".
    case macro(Macro)

    public enum Kind: String, Codable, CaseIterable, Sendable {
        case app, url, file, keystroke, media, screenshot, system, edit, window
        case shortcut, appShortcut, menuItem, clickButtons, appleScript, shell, text, aiPrompt, folder, macro
    }

    public var kind: Kind {
        switch self {
        case .app: .app
        case .url: .url
        case .file: .file
        case .keystroke: .keystroke
        case .media: .media
        case .screenshot: .screenshot
        case .system: .system
        case .edit: .edit
        case .window: .window
        case .shortcut: .shortcut
        case .appShortcut: .appShortcut
        case .menuItem: .menuItem
        case .clickButtons: .clickButtons
        case .appleScript: .appleScript
        case .shell: .shell
        case .text: .text
        case .aiPrompt: .aiPrompt
        case .folder: .folder
        case .macro: .macro
        }
    }

    public var isFolder: Bool { if case .folder = self { true } else { false } }
}

extension Action: Codable {
    private enum CodingKeys: String, CodingKey { case type, value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .app: self = .app(try c.decode(AppTarget.self, forKey: .value))
        case .url: self = .url(try c.decode(WebLink.self, forKey: .value))
        case .file: self = .file(try c.decode(FileTarget.self, forKey: .value))
        case .keystroke: self = .keystroke(try c.decode(KeyCombo.self, forKey: .value))
        case .media: self = .media(try c.decode(MediaCommand.self, forKey: .value))
        case .screenshot: self = .screenshot(try c.decode(ScreenshotOptions.self, forKey: .value))
        case .system: self = .system(try c.decode(SystemCommand.self, forKey: .value))
        case .edit: self = .edit(try c.decode(EditCommand.self, forKey: .value))
        case .window: self = .window(try c.decode(WindowCommand.self, forKey: .value))
        case .shortcut: self = .shortcut(try c.decode(ShortcutRef.self, forKey: .value))
        case .appShortcut: self = .appShortcut(try c.decode(AppShortcut.self, forKey: .value))
        case .menuItem: self = .menuItem(try c.decode(MenuItemRef.self, forKey: .value))
        case .clickButtons: self = .clickButtons(try c.decode(ButtonSequence.self, forKey: .value))
        case .appleScript: self = .appleScript(try c.decode(ScriptSource.self, forKey: .value))
        case .shell: self = .shell(try c.decode(ScriptSource.self, forKey: .value))
        case .text: self = .text(try c.decode(TextSnippet.self, forKey: .value))
        case .aiPrompt: self = .aiPrompt(try c.decode(AIPrompt.self, forKey: .value))
        case .folder: self = .folder(try c.decode(Ring.self, forKey: .value))
        case .macro: self = .macro(try c.decode(Macro.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .type)
        switch self {
        case .app(let v): try c.encode(v, forKey: .value)
        case .url(let v): try c.encode(v, forKey: .value)
        case .file(let v): try c.encode(v, forKey: .value)
        case .keystroke(let v): try c.encode(v, forKey: .value)
        case .media(let v): try c.encode(v, forKey: .value)
        case .screenshot(let v): try c.encode(v, forKey: .value)
        case .system(let v): try c.encode(v, forKey: .value)
        case .edit(let v): try c.encode(v, forKey: .value)
        case .window(let v): try c.encode(v, forKey: .value)
        case .shortcut(let v): try c.encode(v, forKey: .value)
        case .appShortcut(let v): try c.encode(v, forKey: .value)
        case .menuItem(let v): try c.encode(v, forKey: .value)
        case .clickButtons(let v): try c.encode(v, forKey: .value)
        case .appleScript(let v): try c.encode(v, forKey: .value)
        case .shell(let v): try c.encode(v, forKey: .value)
        case .text(let v): try c.encode(v, forKey: .value)
        case .aiPrompt(let v): try c.encode(v, forKey: .value)
        case .folder(let v): try c.encode(v, forKey: .value)
        case .macro(let v): try c.encode(v, forKey: .value)
        }
    }
}

// MARK: - Payloads

public struct AppTarget: Codable, Hashable, Sendable {
    public enum Behavior: String, Codable, CaseIterable, Sendable {
        /// Launch, or bring to front if running.
        case open
        /// Bring to front; if it already is frontmost, hide it.
        case toggle
        /// Quit the app if running.
        case quit
    }

    public var bundleID: String
    public var name: String
    /// Last known bundle path; used for the icon and as a launch fallback.
    public var path: String?
    public var behavior: Behavior

    public init(bundleID: String, name: String, path: String? = nil, behavior: Behavior = .open) {
        self.bundleID = bundleID
        self.name = name
        self.path = path
        self.behavior = behavior
    }
}

public struct WebLink: Codable, Hashable, Sendable {
    /// Any URL string, including deep links (e.g. "obsidian://", "x-apple.systempreferences:").
    public var url: String
    /// Optional browser/app bundle ID to open it with; nil uses the default handler.
    public var openWithBundleID: String?

    public init(url: String, openWithBundleID: String? = nil) {
        self.url = url
        self.openWithBundleID = openWithBundleID
    }
}

public struct FileTarget: Codable, Hashable, Sendable {
    /// Absolute path; "~" is expanded at run time.
    public var path: String
    /// Reveal in Finder instead of opening.
    public var revealInFinder: Bool

    public init(path: String, revealInFinder: Bool = false) {
        self.path = path
        self.revealInFinder = revealInFinder
    }

    public var expandedPath: String { (path as NSString).expandingTildeInPath }
    public var displayName: String { (expandedPath as NSString).lastPathComponent }

    /// True for folders (and app bundles). Falls back to "no extension" when the path is missing.
    public var isDirectory: Bool {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDir) { return isDir.boolValue }
        return expandedPath.hasSuffix("/") || (displayName as NSString).pathExtension.isEmpty
    }
}

public enum MediaCommand: String, Codable, CaseIterable, Sendable {
    case playPause, nextTrack, previousTrack
    case volumeUp, volumeDown, mute
    case brightnessUp, brightnessDown
}

public struct ScreenshotOptions: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable {
        /// Drag to select an area.
        case area
        /// Click a window.
        case window
        /// The whole screen under the cursor.
        case fullScreen
        /// The system screenshot/recording toolbar (⌘⇧5).
        case toolbar
    }

    public var mode: Mode
    /// Copy to the clipboard instead of saving a file (ignored for `.toolbar`).
    public var toClipboard: Bool

    public init(mode: Mode, toClipboard: Bool = false) {
        self.mode = mode
        self.toClipboard = toClipboard
    }
}

public enum SystemCommand: String, Codable, CaseIterable, Sendable {
    case missionControl, appExpose, showDesktop, launchpad
    case notificationCenter, spotlight, siri
    case lockScreen, sleepDisplay, sleep, screenSaver
    case emojiPicker, dictation
    case toggleDarkMode, doNotDisturb
    case forceQuit, systemSettings
}

public enum EditCommand: String, Codable, CaseIterable, Sendable {
    case copy, cut, paste, pasteAndMatchStyle, undo, redo, selectAll, find
}

public enum WindowCommand: String, Codable, CaseIterable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case maximize, center, minimize, toggleFullScreen, nextDisplay, close
}

public struct ShortcutRef: Codable, Hashable, Sendable {
    /// Name of a shortcut in Apple's Shortcuts app.
    public var name: String
    /// Pass the current selection (copied) as the shortcut's input.
    public var passSelection: Bool

    public init(name: String, passSelection: Bool = false) {
        self.name = name
        self.passSelection = passSelection
    }
}

/// How an in-app action reaches its app.
public enum AppDelivery: String, Codable, CaseIterable, Sendable {
    /// Send to the app; if another app is in front, bring this one forward first.
    case bringToFront
    /// Bring the app forward, send, then return to the app you were in (e.g. mute a call
    /// without leaving your document).
    case bringToFrontAndReturn
}

/// A keyboard shortcut that belongs to a specific app.
public struct AppShortcut: Codable, Hashable, Sendable {
    public var bundleID: String
    public var appName: String
    /// What it does, e.g. "Mute / Unmute".
    public var title: String
    public var combo: KeyCombo
    /// SF Symbol shown on the ring, e.g. "mic.slash".
    public var symbol: String?
    public var delivery: AppDelivery

    public init(bundleID: String, appName: String, title: String, combo: KeyCombo, symbol: String? = nil, delivery: AppDelivery = .bringToFront) {
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.combo = combo
        self.symbol = symbol
        self.delivery = delivery
    }
}

/// A command in an app's menu bar, by titles from the top menu down, e.g. ["View", "Show Sidebar"].
public struct MenuItemRef: Codable, Hashable, Sendable {
    public var bundleID: String
    public var appName: String
    public var path: [String]
    public var delivery: AppDelivery

    public init(bundleID: String, appName: String, path: [String], delivery: AppDelivery = .bringToFront) {
        self.bundleID = bundleID
        self.appName = appName
        self.path = path
        self.delivery = delivery
    }
}

/// One control to click, found by its accessible name (what VoiceOver reads).
public struct ButtonStep: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// Names that identify the control; the first one found is clicked (apps rename controls
    /// between versions, e.g. "Record" vs "Record and transcribe").
    public var names: [String]
    /// Skipped when it doesn't appear (e.g. a confirmation that only some versions show).
    public var isOptional: Bool

    public init(id: UUID = UUID(), names: [String], isOptional: Bool = false) {
        self.id = id
        self.names = names
        self.isOptional = isOptional
    }
}

/// Clicks controls in an app's windows in order, waiting for each to appear (menus, dialogs).
/// For actions an app offers only as buttons, without a shortcut or menu command.
public struct ButtonSequence: Codable, Hashable, Sendable {
    public var bundleID: String
    public var appName: String
    /// What it does, e.g. "Start Recording".
    public var title: String
    public var steps: [ButtonStep]
    public var symbol: String?
    public var delivery: AppDelivery

    public init(bundleID: String, appName: String, title: String, steps: [ButtonStep], symbol: String? = nil, delivery: AppDelivery = .bringToFront) {
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.steps = steps
        self.symbol = symbol
        self.delivery = delivery
    }
}

public struct ScriptSource: Codable, Hashable, Sendable {
    public var source: String
    /// Only for shell scripts; nil means the user's login shell (zsh by default).
    public var shell: String?

    public init(source: String, shell: String? = nil) {
        self.source = source
        self.shell = shell
    }
}

public struct TextSnippet: Codable, Hashable, Sendable {
    public enum Method: String, Codable, CaseIterable, Sendable {
        /// Put on the clipboard, press ⌘V, then restore the previous clipboard. Fast and exact.
        case paste
        /// Type it character by character. Works where paste is blocked.
        case type
    }

    /// Supports placeholders: {date}, {time}, {clipboard}, {selection}.
    public var text: String
    public var method: Method
    public var pressReturn: Bool

    public init(text: String, method: Method = .paste, pressReturn: Bool = false) {
        self.text = text
        self.method = method
        self.pressReturn = pressReturn
    }
}

public struct AIPrompt: Codable, Hashable, Sendable {
    public enum Service: String, Codable, CaseIterable, Sendable {
        case chatGPT, claude, perplexity, gemini, custom

        public var displayName: String {
            switch self {
            case .chatGPT: "ChatGPT"
            case .claude: "Claude"
            case .perplexity: "Perplexity"
            case .gemini: "Gemini"
            case .custom: "Custom URL"
            }
        }

        /// URL template with a `{prompt}` placeholder (percent-encoded at run time), or nil when the
        /// service has no prefill URL; the prompt is then copied to the clipboard and the site opened.
        public var urlTemplate: String? {
            switch self {
            case .chatGPT: "https://chatgpt.com/?q={prompt}"
            case .claude: "https://claude.ai/new?q={prompt}"
            case .perplexity: "https://www.perplexity.ai/search?q={prompt}"
            case .gemini: nil
            case .custom: nil
            }
        }

        public var homeURL: String {
            switch self {
            case .chatGPT: "https://chatgpt.com/"
            case .claude: "https://claude.ai/new"
            case .perplexity: "https://www.perplexity.ai/"
            case .gemini: "https://gemini.google.com/app"
            case .custom: ""
            }
        }
    }

    public var service: Service
    /// Prompt text; `{selection}` is replaced by the text selected in the frontmost app.
    public var template: String
    /// For `.custom`: a URL containing `{prompt}`.
    public var customURLTemplate: String?

    public init(service: Service, template: String, customURLTemplate: String? = nil) {
        self.service = service
        self.template = template
        self.customURLTemplate = customURLTemplate
    }

    public var usesSelection: Bool { template.contains("{selection}") }
}

public struct Macro: Codable, Hashable, Sendable {
    public var steps: [MacroStep]
    public init(steps: [MacroStep] = []) { self.steps = steps }
}

public struct MacroStep: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    /// Any action except `.folder` and `.macro`.
    public var action: Action
    /// Pause after this step, in seconds.
    public var delayAfter: Double

    public init(id: UUID = UUID(), action: Action, delayAfter: Double = 0.15) {
        self.id = id
        self.action = action
        self.delayAfter = delayAfter
    }
}
