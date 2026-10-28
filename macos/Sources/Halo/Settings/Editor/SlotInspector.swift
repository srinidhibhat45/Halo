import HaloCore
import SwiftUI

/// The editor's trailing inspector: an overview of the ring when nothing is selected, an
/// "Add App or Action…" card for an empty slot, and for a filled slot a header (what it does,
/// Replace…, Clear) above its details, label, icon, tint and permissions.
struct SlotInspector: View {
    let session: RingEditorSession

    var body: some View {
        Group {
            if let index = session.selectedIndex, let slot = session.selectedSlot {
                if slot.isEmpty {
                    EmptySlotInspector(session: session, index: index)
                } else {
                    SlotEditorForm(session: session, index: index, handle: session.handle(for: slot.id))
                }
            } else {
                RingOverviewInspector(session: session)
            }
        }
        .id(session.selectedSlot?.id)
        .onExitCommand { session.requestFocus(.canvas) }
    }
}

// MARK: - Nothing selected

/// The shown ring at a glance: every slot, with Add… on the empty ones.
private struct RingOverviewInspector: View {
    let session: RingEditorSession

    var body: some View {
        let ring = session.ring
        Form {
            Section {
                HStack(spacing: 12) {
                    ringIcon
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.levels.last?.title ?? session.rootTitle)
                            .font(.headline)
                        Text(purpose)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                Text("Click a slot on the ring to add an app or action, or to change one.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Slots") {
                ForEach(Array(ring.slots.enumerated()), id: \.element.id) { index, slot in
                    OverviewRow(session: session, index: index, slot: slot)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// What this ring is for.
    private var purpose: String {
        if session.isNested { return "A nested ring inside \(session.levels.dropLast().last?.title ?? session.rootTitle)" }
        if let profile = session.profile { return "Replaces Everywhere while \(profile.appName) is in front" }
        return "The ring for every app without its own"
    }

    @ViewBuilder
    private var ringIcon: some View {
        if session.isNested {
            SlotIconTile(icon: .symbol(name: "circle.grid.cross.fill"), size: 40)
        } else if let profile = session.profile {
            IconView(spec: .app(bundleID: profile.bundleID), size: 40)
        } else {
            SlotIconTile(icon: .symbol(name: "globe"), size: 40)
        }
    }
}

/// One slot in the overview: click to select it; empty slots have Add….
private struct OverviewRow: View {
    let session: RingEditorSession
    let index: Int
    let slot: Slot

    var body: some View {
        let inherited = session.inheritedSlot(at: index)
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Button {
                session.select(index)
            } label: {
                HStack(spacing: 10) {
                    icon(inherited: inherited)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(slot.isEmpty ? (inherited?.displayTitle ?? "Empty") : slot.displayTitle)
                            .foregroundStyle(slot.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                        Text(inherited == nil ? session.direction(of: index) : "\(session.direction(of: index)) · from Everywhere")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Select this slot")
            if slot.isEmpty {
                Button(inherited == nil ? "Add…" : "Change…") { session.openPicker(at: index, from: .canvas) }
                    .controlSize(.small)
                    .help(inherited == nil ? "Add an app or action" : "Give \(session.rootTitle) its own action here")
                    .accessibilityLabel(inherited == nil ? "Add to slot \(index + 1)" : "Change slot \(index + 1)")
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func icon(inherited: Slot?) -> some View {
        if slot.isEmpty, inherited == nil {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 24, height: 24)
                .overlay(Circle().strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                .accessibilityHidden(true)
        } else {
            SlotIconTile(icon: (inherited ?? slot).displayIcon, size: 24)
                .opacity(slot.isEmpty ? 0.5 : 1)
        }
    }
}

// MARK: - Empty slot

private struct EmptySlotInspector: View {
    let session: RingEditorSession
    let index: Int

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 46, height: 46)
                        .overlay(Circle().strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Empty Slot")
                            .font(.headline)
                        Text(session.position(of: index))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)

                Button {
                    session.openPicker(at: index, from: .inspector)
                } label: {
                    Label("Add App or Action…", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .popover(isPresented: session.pickerBinding(for: .inspector), arrowEdge: .leading) {
                    RingPickerPopover(session: session)
                }
                .help("Choose what this slot does")
            } footer: {
                Text("You can also drag an app, file or link from Finder or a browser onto the slot.")
            }

            if let inherited = session.inheritedSlot(at: index) {
                Section {
                    HStack(spacing: 10) {
                        SlotIconTile(icon: inherited.displayIcon, size: 28)
                            .opacity(0.6)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(inherited.displayTitle)
                            Text("From Everywhere")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Button("Customize") { session.assign(inherited, at: index) }
                            .controlSize(.small)
                            .help("Copy this action into the \(session.rootTitle) ring so you can change it")
                    }
                } header: {
                    Text("Shown Here Now")
                } footer: {
                    Text("Empty slots in this ring show the action from Everywhere. Add something to give \(session.rootTitle) its own.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Filled slot

private struct SlotEditorForm: View {
    let session: RingEditorSession
    let index: Int
    let handle: SlotHandle

    var body: some View {
        if let slot = handle.slot, let action = slot.action {
            let setupHandled = session.pendingSetupID == handle.slotID && action.kind.editorHandlesSetup
            Form {
                Section {
                    SlotSummaryHeader(slot: slot, summary: action.editorSummary, position: session.position(of: index),
                                      accent: session.model.settings.accent.color)
                    HStack(spacing: 8) {
                        Button {
                            session.openPicker(at: index, from: .inspector)
                        } label: {
                            Label("Replace…", systemImage: "arrow.left.arrow.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .popover(isPresented: session.pickerBinding(for: .inspector), arrowEdge: .leading) {
                            RingPickerPopover(session: session)
                        }
                        .help("Put a different app or action in this slot")

                        Button(role: .destructive) {
                            session.clear(at: index)
                        } label: {
                            Label("Clear", systemImage: "trash")
                        }
                        .help("Empty this slot")
                    }
                    .controlSize(.large)
                }

                ActionDetailsEditor(
                    action: handle.actionBinding(default: action) { "Edit \($0.kind.editorTitle)" },
                    setup: setupBinding,
                    onOpenFolder: { session.enterFolder(at: index) }
                )

                Section("Appearance") {
                    CommittingTextField("Label", text: titleBinding, prompt: action.defaultTitle, focusRequest: labelFocusRequest(enabled: !setupHandled))
                    LabeledContent("Icon") {
                        IconPicker(icon: handle.binding(\.icon, default: nil, actionName: "Change Icon"), defaultIcon: action.defaultIcon)
                    }
                    LabeledContent("Tint") {
                        ColorSwatchPicker(
                            selection: handle.binding(\.tint, default: nil, actionName: "Change Tint"),
                            defaultColor: session.model.settings.accent.color,
                            defaultLabel: "Ring Accent"
                        )
                    }
                }

                PermissionSection(permissions: action.requiredPermissions)
            }
            .formStyle(.grouped)
            .onAppear { PermissionCenter.shared.refresh() }
        }
    }

    /// The label; a write after the slot was cleared is dropped rather than labelling an empty slot.
    private var titleBinding: Binding<String> {
        let handle = handle
        return Binding(
            get: { handle.slot?.title ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                handle.update("Rename Slot") { slot in
                    guard slot.action != nil else { return }
                    slot.title = trimmed.isEmpty ? nil : trimmed
                }
            }
        )
    }

    /// True while a slot just added from a template is waiting for its details.
    private var setupBinding: Binding<Bool> {
        let session = session
        let id = handle.slotID
        return Binding(
            get: { session.pendingSetupID == id },
            set: { pending in
                guard !pending else { return }
                session.pendingSetupID = nil
                if session.focusRequest == .inspector { session.focusRequest = nil }
            }
        )
    }

    /// The label takes focus on Return from the canvas, unless the action's own editor is
    /// collecting setup details.
    private func labelFocusRequest(enabled: Bool) -> Binding<Bool> {
        let session = session
        return Binding(
            get: { enabled && session.focusRequest == .inspector },
            set: { requested in
                guard !requested else { return }
                session.focusRequest = nil
                session.pendingSetupID = nil
            }
        )
    }
}

/// The slot's icon, title, what it does and where it is, at the top of the inspector.
private struct SlotSummaryHeader: View {
    let slot: Slot
    let summary: String
    let position: String
    let accent: Color

    var body: some View {
        let tint = slot.tint?.color ?? accent
        HStack(spacing: 12) {
            IconView(spec: slot.displayIcon, size: 30, symbolColor: tint)
                .frame(width: 52, height: 52)
                .background(tint.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.displayTitle)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(position)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

extension Action {
    /// One line saying what the action does, for the inspector header.
    var editorSummary: String {
        switch self {
        case .app(let target):
            guard !target.bundleID.isEmpty else { return "Opens an app you choose" }
            switch target.behavior {
            case .open: return "Opens \(target.name), or brings it to the front"
            case .toggle: return "Shows \(target.name), or hides it if it's in front"
            case .quit: return "Quits \(target.name)"
            }
        case .url(let link):
            let address = link.url.trimmingCharacters(in: .whitespaces)
            return address.isEmpty || address == "https://" ? "Opens a web page or app link" : "Opens \(defaultTitle)"
        case .file(let file):
            guard !file.path.isEmpty else { return "Opens a file or folder you choose" }
            return file.revealInFinder ? "Shows \(file.displayName) in Finder" : "Opens \(file.displayName)"
        case .keystroke(let combo):
            return "Presses \(combo.displayString) in the front app"
        case .media(let command):
            return Self.catalogSubtitle("media.\(command.rawValue)")
        case .screenshot(let options):
            return options.mode.editorSubtitle
        case .system(let command):
            return Self.catalogSubtitle("system.\(command.rawValue)")
        case .edit(let command):
            return "Sends \(command.keyCombo.displayString) to the front app"
        case .window(let command):
            return Self.catalogSubtitle("window.\(command.rawValue)")
        case .shortcut(let ref):
            return ref.name.isEmpty ? "Runs a shortcut from the Shortcuts app" : "Runs “\(ref.name)” from Shortcuts"
        case .appShortcut(let shortcut):
            guard !shortcut.bundleID.isEmpty else { return "Presses a shortcut in an app you choose" }
            return "Presses \(shortcut.combo.displayString) in \(shortcut.appName)"
        case .menuItem(let item):
            guard !item.bundleID.isEmpty, !item.path.isEmpty else { return "Runs a menu command in an app you choose" }
            return "Chooses \(item.path.joined(separator: " › ")) in \(item.appName)"
        case .appleScript:
            return "Runs an AppleScript"
        case .shell:
            return "Runs a command in your login shell"
        case .text(let snippet):
            return snippet.method == .paste ? "Pastes text into the front app" : "Types text into the front app"
        case .aiPrompt(let prompt):
            return prompt.service == .custom ? "Opens your AI service with a prompt" : "Asks \(prompt.service.displayName) with your prompt"
        case .folder(let ring):
            return ring.filledCount == 1 ? "Opens a ring with 1 action" : "Opens a ring with \(ring.filledCount) actions"
        case .macro(let macro):
            return macro.steps.isEmpty ? "Runs actions one after another" : "Runs \(macro.steps.count) steps in order"
        }
    }

    private static func catalogSubtitle(_ templateID: String) -> String {
        ActionCatalog.template(id: templateID)?.subtitle ?? ""
    }
}

// MARK: - Action type

/// Changes an action's kind, grouped by library category; picks start from the library's
/// default for that kind. (Smart Action steps; slots use Replace….)
struct ActionTypeMenu: View {
    let current: Action.Kind
    var excluded: Set<Action.Kind> = []
    let onChoose: (Action.Kind) -> Void

    var body: some View {
        Menu {
            ForEach(ActionCategory.allCases) { category in
                let kinds = Action.Kind.allCases.filter { $0.editorCategory == category && !excluded.contains($0) }
                if kinds.count == 1, let kind = kinds.first {
                    toggle(for: kind) { Label(category.title, systemImage: category.symbol) }
                } else if !kinds.isEmpty {
                    Menu {
                        ForEach(kinds, id: \.self) { kind in
                            toggle(for: kind) { Label(kind.editorTitle, systemImage: kind.editorSymbol) }
                        }
                    } label: {
                        Label(category.title, systemImage: category.symbol)
                    }
                }
            }
        } label: {
            Label(current.editorTitle, systemImage: current.editorSymbol)
        }
        .fixedSize()
        .accessibilityLabel("Action type")
        .accessibilityValue(current.editorTitle)
    }

    private func toggle(for kind: Action.Kind, @ViewBuilder label: () -> some View) -> some View {
        Toggle(isOn: Binding(get: { kind == current }, set: { on in if on, kind != current { onChoose(kind) } }), label: label)
    }
}

extension Action.Kind {
    /// Name in the action type menu and section headers.
    var editorTitle: String {
        switch self {
        case .app: "App"
        case .url: "Website or Link"
        case .file: "File or Folder"
        case .keystroke: "Keyboard Shortcut"
        case .media: "Media Control"
        case .screenshot: "Screenshot"
        case .system: "System Action"
        case .edit: "Edit Command"
        case .window: "Window Layout"
        case .shortcut: "Apple Shortcut"
        case .appShortcut: "App Shortcut"
        case .menuItem: "Menu Command"
        case .appleScript: "AppleScript"
        case .shell: "Shell Script"
        case .text: "Text Snippet"
        case .aiPrompt: "AI Prompt"
        case .folder: "Nested Ring"
        case .macro: "Smart Action"
        }
    }

    var editorSymbol: String {
        switch self {
        case .appleScript: "applescript"
        case .shell: "terminal"
        default: editorCategory.symbol
        }
    }

    /// The library category this kind is listed under (as `Action.category`).
    var editorCategory: ActionCategory {
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

    /// A sensible starting action of this kind: the library's "needs setup" template for it,
    /// else its first template.
    var editorDefaultAction: Action {
        let templates = ActionCatalog.all.filter { $0.action.kind == self }
        guard let template = templates.first(where: \.needsSetup) ?? templates.first else {
            return .text(TextSnippet(text: ""))
        }
        if case .folder(let ring) = template.action { return .folder(AppModel.freshIDs(ring)) }
        return template.action
    }

    /// Kinds whose editor collects setup details itself (opens a picker, starts recording,
    /// focuses its main field) right after the slot is added.
    var editorHandlesSetup: Bool {
        switch self {
        case .app, .url, .file, .keystroke, .shortcut, .appleScript, .shell, .text, .aiPrompt: true
        default: false
        }
    }
}

// MARK: - Permissions

/// Missing permissions for the action, each with a Grant button.
private struct PermissionSection: View {
    let permissions: Set<Permission>

    var body: some View {
        let center = PermissionCenter.shared
        let missing = Permission.allCases.filter { permissions.contains($0) && center.status($0) != .granted }
        if !missing.isEmpty {
            Section {
                ForEach(missing, id: \.self) { permission in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: PermissionCenter.symbol(permission))
                            .font(.title3)
                            .foregroundStyle(.orange)
                            .frame(width: 24)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Needs \(PermissionCenter.title(permission)) Permission")
                                .font(.callout.weight(.medium))
                            Text(PermissionCenter.reason(permission))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Button("Grant…") { center.request(permission) }
                            .controlSize(.small)
                            .accessibilityLabel("Grant \(PermissionCenter.title(permission)) permission")
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Permissions")
            }
        }
    }
}

/// A one-line status message inside the inspector.
struct InspectorNote: View {
    enum Tone {
        case info, success, warning, error

        var symbol: String {
            switch self {
            case .info: "info.circle.fill"
            case .success: "checkmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "xmark.octagon.fill"
            }
        }

        var color: Color {
            switch self {
            case .info: .secondary
            case .success: .green
            case .warning: .orange
            case .error: .red
            }
        }
    }

    let tone: Tone
    let text: String

    init(_ tone: Tone, _ text: String) {
        self.tone = tone
        self.text = text
    }

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: tone.symbol)
                .foregroundStyle(tone.color)
        }
        .font(.caption)
    }
}
