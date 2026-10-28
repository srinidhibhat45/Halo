import AppKit
import HaloCore
import SwiftUI

/// The per-kind editor for an action: inspector sections for a slot, or plain rows for a Smart
/// Action step. Every change writes the whole action back through `action` (one undo step).
struct ActionDetailsEditor: View {
    @Binding var action: Action
    /// True right after the slot was added from a "needs setup" template; the kind's editor
    /// collects the details (opens a picker, starts recording…) and resets it.
    @Binding var setup: Bool
    /// Opens a nested ring in the editor; nil inside Smart Action steps.
    var onOpenFolder: (() -> Void)?
    /// Sections (slot inspector) or plain rows (inside a Smart Action step).
    var inSections = true

    var body: some View {
        switch action {
        case .app(let target):
            group("App", footer: target.behavior.editorExplanation) {
                AppActionEditor(target: payload(target, { if case .app(let v) = $0 { v } else { nil } }, Action.app), setup: $setup)
            }
        case .url(let link):
            group("Website or Link", footer: "Web addresses open in a browser. App links, such as obsidian:// or x-apple.systempreferences:, open their app.") {
                URLActionEditor(link: payload(link, { if case .url(let v) = $0 { v } else { nil } }, Action.url), setup: $setup)
            }
        case .file(let file):
            group("File or Folder") {
                FileActionEditor(file: payload(file, { if case .file(let v) = $0 { v } else { nil } }, Action.file), setup: $setup)
            }
        case .keystroke(let combo):
            group("Keyboard Shortcut", footer: "Halo presses these keys in the app that was in front when you opened the ring.") {
                LabeledContent("Keys") {
                    ShortcutRecorder(combo: keystrokeBinding(combo), purpose: .keystroke)
                        .shortcutRecorderStartRequest($setup)
                }
            }
        case .media(let command):
            group("Media Control", footer: Self.subtitle("media.\(command.rawValue)")) {
                CommandTileGrid(commands: MediaCommand.allCases,
                                selection: payload(command, { if case .media(let v) = $0 { v } else { nil } }, Action.media),
                                title: \.title, symbol: \.symbol) { Self.subtitle("media.\($0.rawValue)") }
            }
        case .screenshot(let options):
            group("Screenshot", footer: options.mode.editorSubtitle) {
                ScreenshotActionEditor(options: payload(options, { if case .screenshot(let v) = $0 { v } else { nil } }, Action.screenshot))
            }
        case .system(let command):
            group("System Action", footer: Self.subtitle("system.\(command.rawValue)")) {
                CommandTileGrid(commands: SystemCommand.allCases,
                                selection: payload(command, { if case .system(let v) = $0 { v } else { nil } }, Action.system),
                                title: \.title, symbol: \.symbol) { Self.subtitle("system.\($0.rawValue)") }
            }
        case .edit(let command):
            group("Edit Command", footer: Self.subtitle("edit.\(command.rawValue)")) {
                CommandTileGrid(commands: EditCommand.allCases,
                                selection: payload(command, { if case .edit(let v) = $0 { v } else { nil } }, Action.edit),
                                title: \.title, symbol: \.symbol) { Self.subtitle("edit.\($0.rawValue)") }
            }
        case .window(let command):
            group("Window Layout", footer: Self.subtitle("window.\(command.rawValue)")) {
                CommandTileGrid(commands: WindowCommand.allCases,
                                selection: payload(command, { if case .window(let v) = $0 { v } else { nil } }, Action.window),
                                title: \.title, symbol: \.symbol) { Self.subtitle("window.\($0.rawValue)") }
            }
        case .shortcut(let ref):
            group("Apple Shortcut", footer: "Shortcuts run by name, so renaming one in the Shortcuts app disconnects it from this slot.") {
                ShortcutActionEditor(ref: payload(ref, { if case .shortcut(let v) = $0 { v } else { nil } }, Action.shortcut), setup: $setup)
            }
        case .appShortcut(let shortcut):
            group("App Shortcut", footer: "A shortcut from the app's own documentation. Halo presses it in that app.") {
                AppShortcutEditor(shortcut: payload(shortcut, { if case .appShortcut(let v) = $0 { v } else { nil } }, Action.appShortcut), setup: $setup)
            }
        case .menuItem(let item):
            group("Menu Command", footer: "Any command in the app's menu bar, by name. If the app renames it, choose it again.") {
                MenuItemEditor(item: payload(item, { if case .menuItem(let v) = $0 { v } else { nil } }, Action.menuItem), setup: $setup)
            }
        case .clickButtons(let sequence):
            group("Click Buttons", footer: "For actions an app offers only as buttons. Works while the app shows those buttons, e.g. during a meeting.") {
                ButtonSequenceEditor(sequence: payload(sequence, { if case .clickButtons(let v) = $0 { v } else { nil } }, Action.clickButtons), setup: $setup)
            }
        case .appleScript(let source):
            group("AppleScript", footer: "Runs with Automation permission; the first run asks to control each app the script talks to.") {
                ScriptActionEditor(source: payload(source, { if case .appleScript(let v) = $0 { v } else { nil } }, Action.appleScript), isShell: false, setup: $setup)
            }
        case .shell(let source):
            group("Shell Script", footer: "Runs in the background with your login environment. Output is discarded; a non-zero exit shows an error.") {
                ScriptActionEditor(source: payload(source, { if case .shell(let v) = $0 { v } else { nil } }, Action.shell), isShell: true, setup: $setup)
            }
        case .text(let snippet):
            group("Text Snippet", footer: "Placeholders are filled in when the snippet runs.") {
                TextSnippetEditor(snippet: payload(snippet, { if case .text(let v) = $0 { v } else { nil } }, Action.text), setup: $setup)
            }
        case .aiPrompt(let prompt):
            group("AI Prompt", footer: prompt.service.editorExplanation) {
                AIPromptEditor(prompt: payload(prompt, { if case .aiPrompt(let v) = $0 { v } else { nil } }, Action.aiPrompt), setup: $setup)
            }
        case .folder(let ring):
            group("Nested Ring", footer: "Choosing this slot replaces the ring with this one. Press Esc or click the centre to go back.") {
                if let onOpenFolder {
                    FolderActionEditor(ring: payload(ring, { if case .folder(let v) = $0 { v } else { nil } }, Action.folder), onOpen: onOpenFolder)
                } else {
                    InspectorNote(.warning, "Nested rings can't be a step of a Smart Action.")
                }
            }
        case .macro(let macro):
            if inSections {
                MacroActionEditor(macro: payload(macro, { if case .macro(let v) = $0 { v } else { nil } }, Action.macro))
            } else {
                InspectorNote(.warning, "A Smart Action can't contain another Smart Action.")
            }
        }
    }

    @ViewBuilder
    private func group(_ title: String, footer: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        if inSections {
            Section {
                content()
            } header: {
                Text(title)
            } footer: {
                if let footer { Text(footer) }
            }
        } else {
            content()
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// A binding to the action's payload of one kind. Writes are dropped once the action is no
    /// longer of that kind (a draft committed as the editor goes away after a type change).
    private func payload<Payload>(_ current: Payload, _ extract: @escaping (Action) -> Payload?, _ embed: @escaping (Payload) -> Action) -> Binding<Payload> {
        let action = $action
        return Binding(
            get: { extract(action.wrappedValue) ?? current },
            set: { newValue in
                guard extract(action.wrappedValue) != nil else { return }
                action.wrappedValue = embed(newValue)
            }
        )
    }

    /// The recorder clears with nil; a keystroke action always keeps a combo.
    private func keystrokeBinding(_ current: KeyCombo) -> Binding<KeyCombo?> {
        let action = $action
        return Binding(
            get: { if case .keystroke(let combo) = action.wrappedValue { combo } else { current } },
            set: { newValue in
                guard let newValue, case .keystroke = action.wrappedValue else { return }
                action.wrappedValue = .keystroke(newValue)
            }
        )
    }

    private static func subtitle(_ templateID: String) -> String {
        ActionCatalog.template(id: templateID)?.subtitle ?? ""
    }
}

// MARK: - App

private struct AppActionEditor: View {
    @Binding var target: AppTarget
    @Binding var setup: Bool
    @ViewState private var showsPicker = false

    var body: some View {
        LabeledContent("App") {
            Button {
                showsPicker = true
            } label: {
                HStack(spacing: 6) {
                    if !target.bundleID.isEmpty {
                        Image(nsImage: AppCatalog.shared.icon(forBundleID: target.bundleID))
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 18, height: 18)
                            .accessibilityHidden(true)
                    }
                    Text(target.bundleID.isEmpty ? "Choose App…" : target.name)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .popover(isPresented: $showsPicker, arrowEdge: .leading) {
                AppPickerView(selectedBundleID: target.bundleID) { app in
                    target = AppTarget(bundleID: app.bundleID, name: app.name, path: app.url.path(percentEncoded: false), behavior: target.behavior)
                    showsPicker = false
                }
                .frame(width: 320, height: 440)
            }
            .accessibilityLabel("App")
            .accessibilityValue(target.bundleID.isEmpty ? "None chosen" : target.name)
        }
        .onChange(of: setup, initial: true) { _, pending in
            guard pending else { return }
            setup = false
            // Present after the row has appeared.
            Task { @MainActor in showsPicker = true }
        }
        if target.bundleID.isEmpty {
            InspectorNote(.warning, "Choose the app this slot opens.")
        } else if AppCatalog.shared.info(bundleID: target.bundleID) == nil {
            InspectorNote(.warning, "\(target.name) isn't installed on this Mac.")
        }
        Picker("When Chosen", selection: $target.behavior) {
            ForEach(AppTarget.Behavior.allCases, id: \.self) { behavior in
                Text(behavior.editorTitle).tag(behavior)
            }
        }
        .pickerStyle(.segmented)
    }
}

extension AppTarget.Behavior {
    var editorTitle: String {
        switch self {
        case .open: "Open"
        case .toggle: "Show or Hide"
        case .quit: "Quit"
        }
    }

    var editorExplanation: String {
        switch self {
        case .open: "Opens the app, or brings it to the front if it's already running."
        case .toggle: "Brings the app to the front, or hides it if it's already in front."
        case .quit: "Quits the app if it's running."
        }
    }
}

// MARK: - URL

private struct URLActionEditor: View {
    @Binding var link: WebLink
    @Binding var setup: Bool
    @ViewState private var handlers: [AppInfo] = []

    var body: some View {
        CommittingTextField("Address", text: $link.url, prompt: "https://example.com", focusRequest: $setup)
        checkRow
        Picker("Open With", selection: $link.openWithBundleID) {
            Text(defaultHandlerTitle).tag(String?.none)
            if !handlers.isEmpty { Divider() }
            ForEach(handlers) { app in
                Label {
                    Text(app.name)
                } icon: {
                    Image(nsImage: AppCatalog.shared.icon(forBundleID: app.bundleID))
                }
                .tag(String?.some(app.bundleID))
            }
            if let chosen = link.openWithBundleID, !handlers.contains(where: { $0.bundleID == chosen }) {
                Text(AppCatalog.shared.info(bundleID: chosen)?.name ?? chosen).tag(String?.some(chosen))
            }
        }
        .task(id: Self.handlerKey(for: link.url)) {
            handlers = Self.handlers(for: link.url)
        }
    }

    @ViewBuilder
    private var checkRow: some View {
        switch Self.check(link.url) {
        case .empty:
            InspectorNote(.info, "Enter a web address or an app link.")
        case .needsScheme(let suggestion):
            HStack {
                InspectorNote(.warning, "Add https:// to open this in a browser.")
                Spacer(minLength: 0)
                Button("Use https://") { link.url = suggestion }
                    .controlSize(.small)
            }
        case .invalid(let message):
            InspectorNote(.error, message)
        case .unhandled(let scheme):
            InspectorNote(.warning, "No app on this Mac opens “\(scheme):” links.")
        case .opens(let appName):
            InspectorNote(.success, "Opens in \(chosenName ?? appName).")
        }
    }

    private var chosenName: String? {
        link.openWithBundleID.flatMap { AppCatalog.shared.info(bundleID: $0)?.name }
    }

    private var defaultHandlerTitle: String {
        guard let url = Self.probeURL(for: link.url),
              let app = NSWorkspace.shared.urlForApplication(toOpen: url),
              let info = AppCatalog.appInfo(at: app) else { return "Default App" }
        return "Default (\(info.name))"
    }

    enum Check {
        case empty
        case needsScheme(String)
        case invalid(String)
        case unhandled(String)
        case opens(String)
    }

    static func check(_ raw: String) -> Check {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text == "https://" || text == "http://" { return .empty }
        if text.contains(" ") { return .invalid("Addresses can't contain spaces.") }
        guard let url = URL(string: text) else { return .invalid("This isn't a valid address.") }
        guard let scheme = url.scheme?.lowercased(), !scheme.isEmpty else {
            return text.contains(".") ? .needsScheme("https://" + text) : .invalid("Start with https:// or an app's link prefix, such as obsidian://.")
        }
        if scheme == "http" || scheme == "https", (url.host(percentEncoded: false) ?? "").isEmpty {
            return .invalid("Add a domain, such as example.com.")
        }
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: url) else { return .unhandled(scheme) }
        return .opens(AppCatalog.appInfo(at: app)?.name ?? app.deletingPathExtension().lastPathComponent)
    }

    /// The URL to ask Launch Services about: the address itself, or a web page while it's
    /// incomplete.
    private static func probeURL(for raw: String) -> URL? {
        if let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme != nil { return url }
        return URL(string: "https://example.com")
    }

    private static func handlerKey(for raw: String) -> String {
        probeURL(for: raw)?.scheme?.lowercased() ?? ""
    }

    /// Apps that can open the address, sorted by name.
    private static func handlers(for raw: String) -> [AppInfo] {
        guard let url = probeURL(for: raw) else { return [] }
        var seen = Set<String>()
        return NSWorkspace.shared.urlsForApplications(toOpen: url)
            .compactMap(AppCatalog.appInfo(at:))
            .filter { seen.insert($0.bundleID).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

// MARK: - File

private struct FileActionEditor: View {
    @Binding var file: FileTarget
    @Binding var setup: Bool

    var body: some View {
        Group {
            if file.path.isEmpty {
                Button("Choose File or Folder…", systemImage: "folder", action: choose)
            } else {
                HStack(spacing: 10) {
                    Image(nsImage: AppCatalog.shared.icon(forPath: file.path))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 32, height: 32)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.displayName)
                            .lineLimit(1)
                        Text(file.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                    Button("Choose…", action: choose)
                    Button("Show in Finder", systemImage: "arrow.forward.circle") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.expandedPath)])
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Show in Finder")
                    .disabled(!exists)
                }
                .accessibilityElement(children: .contain)
            }
        }
        .onChange(of: setup, initial: true) { _, pending in
            guard pending else { return }
            setup = false
            choose()
        }
        if !file.path.isEmpty, !exists {
            InspectorNote(.warning, "Halo can't find this item. It may have been moved or renamed.")
        }
        Toggle("Reveal in Finder instead of opening", isOn: $file.revealInFinder)
    }

    private var exists: Bool { FileManager.default.fileExists(atPath: file.expandedPath) }

    private func choose() {
        Task { @MainActor in
            guard let url = await EditorOpenPanel.chooseFileOrFolder() else { return }
            file.path = (url.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
        }
    }
}

// MARK: - Commands

/// A grid of tiles, one per command, each with its symbol and title (subtitle as tooltip and
/// accessibility hint).
private struct CommandTileGrid<Command: Hashable>: View {
    let commands: [Command]
    @Binding var selection: Command
    let title: (Command) -> String
    let symbol: (Command) -> String
    let subtitle: (Command) -> String

    init(commands: [Command], selection: Binding<Command>, title: @escaping (Command) -> String,
         symbol: @escaping (Command) -> String, subtitle: @escaping (Command) -> String) {
        self.commands = commands
        self._selection = selection
        self.title = title
        self.symbol = symbol
        self.subtitle = subtitle
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 6)], spacing: 6) {
            ForEach(commands, id: \.self) { command in
                let isSelected = command == selection
                Button {
                    selection = command
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: symbol(command))
                            .font(.system(size: 17))
                            .symbolRenderingMode(.hierarchical)
                            .frame(height: 22)
                        Text(title(command))
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .lineLimit(2, reservesSpace: true)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .background(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 1.5)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(subtitle(command))
                .accessibilityLabel(title(command))
                .accessibilityHint(subtitle(command))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Screenshot

private struct ScreenshotActionEditor: View {
    @Binding var options: ScreenshotOptions

    var body: some View {
        CommandTileGrid(commands: ScreenshotOptions.Mode.allCases, selection: $options.mode,
                        title: \.editorTitle, symbol: { ScreenshotOptions(mode: $0).symbol }, subtitle: \.editorSubtitle)
        Toggle("Copy to the clipboard instead of saving a file", isOn: $options.toClipboard)
            .disabled(options.mode == .toolbar)
    }
}

extension ScreenshotOptions.Mode {
    var editorTitle: String {
        switch self {
        case .area: "Area"
        case .window: "Window"
        case .fullScreen: "Screen"
        case .toolbar: "Toolbar"
        }
    }

    var editorSubtitle: String {
        switch self {
        case .area: "Drag to capture part of the screen."
        case .window: "Click a window to capture it."
        case .fullScreen: "Captures the screen under the pointer."
        case .toolbar: "Opens the screenshot and recording toolbar (⇧⌘5), with its own options."
        }
    }
}
