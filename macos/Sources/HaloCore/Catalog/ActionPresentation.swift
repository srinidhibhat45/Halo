import Foundation

/// Groups shown in the action library.
public enum ActionCategory: String, CaseIterable, Identifiable, Sendable {
    case apps, inApp, web, files, media, screenshots, system, edit, window, keyboard
    case shortcuts, scripts, text, ai, folders, macros

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .apps: "Apps"
        case .inApp: "In-App Actions"
        case .web: "Websites & Links"
        case .files: "Files & Folders"
        case .media: "Media"
        case .screenshots: "Screenshots"
        case .system: "System"
        case .edit: "Edit"
        case .window: "Windows"
        case .keyboard: "Keyboard Shortcut"
        case .shortcuts: "Shortcuts"
        case .scripts: "Scripts"
        case .text: "Text Snippets"
        case .ai: "AI Prompts"
        case .folders: "Nested Rings"
        case .macros: "Smart Actions"
        }
    }

    public var symbol: String {
        switch self {
        case .apps: "square.grid.2x2"
        case .inApp: "app.badge.checkmark"
        case .web: "globe"
        case .files: "folder"
        case .media: "playpause"
        case .screenshots: "camera.viewfinder"
        case .system: "gearshape"
        case .edit: "doc.on.clipboard"
        case .window: "macwindow"
        case .keyboard: "command"
        case .shortcuts: "square.2.layers.3d"
        case .scripts: "terminal"
        case .text: "text.cursor"
        case .ai: "sparkles"
        case .folders: "circle.grid.cross"
        case .macros: "wand.and.stars"
        }
    }
}

/// macOS permissions an action may need at run time.
public enum Permission: String, CaseIterable, Sendable {
    /// Posting keystrokes, media keys, moving windows, reading the selection.
    case accessibility
    /// Controlling other apps with Apple Events (AppleScript, dark mode toggle).
    case automation
    /// Capturing the screen with `screencapture`.
    case screenRecording
}

public extension Action {
    var category: ActionCategory {
        switch self {
        case .app: .apps
        case .url: .web
        case .file: .files
        case .keystroke: .keyboard
        case .media: .media
        case .screenshot: .screenshots
        case .system: .system
        case .edit: .edit
        case .window: .window
        case .shortcut: .shortcuts
        case .appShortcut, .menuItem: .inApp
        case .appleScript, .shell: .scripts
        case .text: .text
        case .aiPrompt: .ai
        case .folder: .folders
        case .macro: .macros
        }
    }

    /// Default label when the slot has no custom title.
    var defaultTitle: String {
        switch self {
        case .app(let t):
            switch t.behavior {
            case .open, .toggle: return t.name
            case .quit: return "Quit \(t.name)"
            }
        case .url(let l): return Self.hostLabel(for: l.url)
        case .file(let f): return f.displayName.isEmpty ? "File" : f.displayName
        case .keystroke(let k): return k.displayString
        case .media(let m): return m.title
        case .screenshot(let s): return s.title
        case .system(let s): return s.title
        case .edit(let e): return e.title
        case .window(let w): return w.title
        case .shortcut(let s): return s.name.isEmpty ? "Shortcut" : s.name
        case .appShortcut(let s): return s.title.isEmpty ? "\(s.appName) Shortcut" : s.title
        case .menuItem(let m): return m.path.last ?? "Menu Command"
        case .appleScript: return "AppleScript"
        case .shell: return "Shell Script"
        case .text(let t): return t.text.isEmpty ? "Text" : Self.preview(t.text)
        case .aiPrompt(let p): return "Ask \(p.service == .custom ? "AI" : p.service.displayName)"
        case .folder: return "Folder"
        case .macro(let m): return m.steps.isEmpty ? "Smart Action" : "Smart Action (\(m.steps.count))"
        }
    }

    /// SF Symbol used when the slot has no custom icon. App actions use the app's icon instead
    /// (see `defaultIcon`); this is their fallback.
    var defaultSymbol: String {
        switch self {
        case .app: "app.dashed"
        case .url: "globe"
        case .file(let f): f.isDirectory ? "folder.fill" : "doc.fill"
        case .keystroke: "command"
        case .media(let m): m.symbol
        case .screenshot(let s): s.symbol
        case .system(let s): s.symbol
        case .edit(let e): e.symbol
        case .window(let w): w.symbol
        case .shortcut: "square.2.layers.3d.fill"
        case .appShortcut(let s): s.symbol ?? "command"
        case .menuItem: "filemenu.and.selection"
        case .appleScript: "applescript.fill"
        case .shell: "terminal.fill"
        case .text: "text.cursor"
        case .aiPrompt: "sparkles"
        case .folder: "circle.grid.cross.fill"
        case .macro: "wand.and.stars"
        }
    }

    /// The icon to draw by default.
    var defaultIcon: IconSpec {
        switch self {
        case .app(let t): .app(bundleID: t.bundleID)
        default: .symbol(name: defaultSymbol)
        }
    }

    /// Permissions needed to run this action (macros: the union of their steps).
    var requiredPermissions: Set<Permission> {
        switch self {
        case .keystroke, .media, .edit, .window, .text, .appShortcut, .menuItem: [.accessibility]
        // Screenshots go through the system's own ⇧⌘3/⇧⌘4 shortcuts (Accessibility only);
        // the toolbar opens Screenshot.app and needs nothing.
        case .screenshot(let s): s.mode == .toolbar ? [] : [.accessibility]
        case .system(let s): s.requiredPermissions
        case .appleScript: [.automation]
        case .shortcut(let s): s.passSelection ? [.accessibility] : []
        case .aiPrompt(let p): p.usesSelection ? [.accessibility] : []
        case .macro(let m): m.steps.reduce(into: Set<Permission>()) { $0.formUnion($1.action.requiredPermissions) }
        case .app, .url, .file, .shell, .folder: []
        }
    }

    /// The title a slot shows: custom title, else the action's default, else "Empty".
    static func title(for slot: Slot) -> String {
        if let t = slot.title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        return slot.action?.defaultTitle ?? "Empty"
    }

    /// The icon a slot shows, or nil for an empty slot.
    static func icon(for slot: Slot) -> IconSpec? {
        slot.icon ?? slot.action?.defaultIcon
    }

    private static func hostLabel(for urlString: String) -> String {
        guard let url = URL(string: urlString) else { return urlString.isEmpty ? "Link" : urlString }
        if let host = url.host(percentEncoded: false), !host.isEmpty {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        return url.scheme.map { "\($0) link" } ?? "Link"
    }

    private static func preview(_ text: String) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return firstLine.count > 24 ? String(firstLine.prefix(23)) + "…" : firstLine
    }
}

public extension Slot {
    var displayTitle: String { Action.title(for: self) }
    var displayIcon: IconSpec? { Action.icon(for: self) }
}

// MARK: - Titles and symbols for enum payloads

public extension MediaCommand {
    var title: String {
        switch self {
        case .playPause: "Play/Pause"
        case .nextTrack: "Next Track"
        case .previousTrack: "Previous Track"
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .mute: "Mute"
        case .brightnessUp: "Brightness Up"
        case .brightnessDown: "Brightness Down"
        }
    }

    var symbol: String {
        switch self {
        case .playPause: "playpause.fill"
        case .nextTrack: "forward.fill"
        case .previousTrack: "backward.fill"
        case .volumeUp: "speaker.wave.3.fill"
        case .volumeDown: "speaker.wave.1.fill"
        case .mute: "speaker.slash.fill"
        case .brightnessUp: "sun.max.fill"
        case .brightnessDown: "sun.min.fill"
        }
    }
}

public extension ScreenshotOptions {
    var title: String {
        switch mode {
        case .area: toClipboard ? "Copy Area" : "Screenshot Area"
        case .window: toClipboard ? "Copy Window" : "Screenshot Window"
        case .fullScreen: toClipboard ? "Copy Screen" : "Screenshot"
        case .toolbar: "Screenshot Tools"
        }
    }

    var symbol: String {
        switch mode {
        case .area: "rectangle.dashed"
        case .window: "macwindow"
        case .fullScreen: "display"
        case .toolbar: "camera.viewfinder"
        }
    }
}

public extension SystemCommand {
    var title: String {
        switch self {
        case .missionControl: "Mission Control"
        case .appExpose: "App Windows"
        case .showDesktop: "Show Desktop"
        case .launchpad: "Apps"
        case .notificationCenter: "Notification Center"
        case .spotlight: "Spotlight"
        case .siri: "Siri"
        case .lockScreen: "Lock Screen"
        case .sleepDisplay: "Display Sleep"
        case .sleep: "Sleep"
        case .screenSaver: "Screen Saver"
        case .emojiPicker: "Emoji & Symbols"
        case .dictation: "Dictation"
        case .toggleDarkMode: "Dark Mode"
        case .doNotDisturb: "Do Not Disturb"
        case .forceQuit: "Force Quit…"
        case .systemSettings: "System Settings"
        }
    }

    var symbol: String {
        switch self {
        case .missionControl: "rectangle.3.group"
        case .appExpose: "rectangle.stack"
        case .showDesktop: "menubar.dock.rectangle"
        case .launchpad: "square.grid.3x3.fill"
        case .notificationCenter: "bell.badge"
        case .spotlight: "magnifyingglass"
        case .siri: "waveform"
        case .lockScreen: "lock.fill"
        case .sleepDisplay: "moon.fill"
        case .sleep: "powersleep"
        case .screenSaver: "sparkles.tv"
        case .emojiPicker: "face.smiling"
        case .dictation: "mic.fill"
        case .toggleDarkMode: "circle.lefthalf.filled"
        case .doNotDisturb: "moon.circle.fill"
        case .forceQuit: "xmark.octagon.fill"
        case .systemSettings: "gearshape.fill"
        }
    }

    var requiredPermissions: Set<Permission> {
        switch self {
        case .toggleDarkMode: [.automation]
        case .notificationCenter, .spotlight, .lockScreen, .emojiPicker, .dictation, .doNotDisturb, .forceQuit:
            [.accessibility]
        case .missionControl, .appExpose, .showDesktop, .launchpad, .siri,
             .sleepDisplay, .sleep, .screenSaver, .systemSettings:
            []
        }
    }
}

public extension EditCommand {
    var title: String {
        switch self {
        case .copy: "Copy"
        case .cut: "Cut"
        case .paste: "Paste"
        case .pasteAndMatchStyle: "Paste as Plain Text"
        case .undo: "Undo"
        case .redo: "Redo"
        case .selectAll: "Select All"
        case .find: "Find"
        }
    }

    var symbol: String {
        switch self {
        case .copy: "doc.on.doc"
        case .cut: "scissors"
        case .paste: "doc.on.clipboard"
        case .pasteAndMatchStyle: "doc.plaintext"
        case .undo: "arrow.uturn.backward"
        case .redo: "arrow.uturn.forward"
        case .selectAll: "selection.pin.in.out"
        case .find: "text.magnifyingglass"
        }
    }

    /// The standard key combo this command sends.
    var keyCombo: KeyCombo {
        switch self {
        case .copy: KeyCombo(keyCode: KeyCode.c, modifiers: .command, keyLabel: "C")
        case .cut: KeyCombo(keyCode: KeyCode.x, modifiers: .command, keyLabel: "X")
        case .paste: KeyCombo(keyCode: KeyCode.v, modifiers: .command, keyLabel: "V")
        case .pasteAndMatchStyle: KeyCombo(keyCode: KeyCode.v, modifiers: [.option, .shift, .command], keyLabel: "V")
        case .undo: KeyCombo(keyCode: KeyCode.z, modifiers: .command, keyLabel: "Z")
        case .redo: KeyCombo(keyCode: KeyCode.z, modifiers: [.shift, .command], keyLabel: "Z")
        case .selectAll: KeyCombo(keyCode: KeyCode.a, modifiers: .command, keyLabel: "A")
        case .find: KeyCombo(keyCode: KeyCode.f, modifiers: .command, keyLabel: "F")
        }
    }
}

public extension WindowCommand {
    var title: String {
        switch self {
        case .leftHalf: "Left Half"
        case .rightHalf: "Right Half"
        case .topHalf: "Top Half"
        case .bottomHalf: "Bottom Half"
        case .maximize: "Fill Screen"
        case .center: "Center"
        case .minimize: "Minimize"
        case .toggleFullScreen: "Full Screen"
        case .nextDisplay: "Next Display"
        case .close: "Close Window"
        }
    }

    var symbol: String {
        switch self {
        case .leftHalf: "rectangle.lefthalf.filled"
        case .rightHalf: "rectangle.righthalf.filled"
        case .topHalf: "rectangle.tophalf.filled"
        case .bottomHalf: "rectangle.bottomhalf.filled"
        case .maximize: "rectangle.inset.filled"
        case .center: "rectangle.center.inset.filled"
        case .minimize: "minus.rectangle"
        case .toggleFullScreen: "arrow.up.left.and.arrow.down.right"
        case .nextDisplay: "display.2"
        case .close: "xmark.rectangle"
        }
    }
}
