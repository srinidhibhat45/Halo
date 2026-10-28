import AppKit
import HaloCore
import SwiftUI

// MARK: - App Shortcut

/// An app's own keyboard shortcut (Teams' Mute, Zoom's Raise Hand…), with ready-made presets
/// for apps Halo knows.
struct AppShortcutEditor: View {
    @Binding var shortcut: AppShortcut
    @Binding var setup: Bool
    @ViewState private var recordsKeys = false

    var body: some View {
        InAppTargetRow(bundleID: shortcut.bundleID, appName: shortcut.appName, setup: $setup) { app in
            shortcut.bundleID = app.bundleID
            shortcut.appName = app.name
            // Start from the app's first preset when it has some, so the slot works at once.
            if shortcut.title.isEmpty, let preset = AppActionPresets.presets(forBundleID: app.bundleID).first {
                apply(preset)
            } else {
                recordsKeys = true
            }
        }

        let presets = AppActionPresets.presets(forBundleID: shortcut.bundleID).filter { $0.combo != nil }
        if !presets.isEmpty {
            LabeledContent("Preset") {
                Menu {
                    ForEach(presets) { preset in
                        Button {
                            apply(preset)
                        } label: {
                            Label("\(preset.title)  \(preset.how)", systemImage: preset.symbol)
                        }
                    }
                } label: {
                    Text(currentPreset(in: presets)?.title ?? "Custom")
                }
                .fixedSize()
            }
        }

        CommittingTextField("Name", text: $shortcut.title, prompt: "What it does, e.g. Mute")
        LabeledContent("Keys") {
            ShortcutRecorder(combo: comboBinding, purpose: .keystroke)
                .shortcutRecorderStartRequest($recordsKeys)
        }
        DeliveryPicker(delivery: $shortcut.delivery, appName: shortcut.appName)
    }

    private var comboBinding: Binding<KeyCombo?> {
        Binding(get: { shortcut.combo }, set: { if let combo = $0 { shortcut.combo = combo } })
    }

    private func currentPreset(in presets: [AppActionPreset]) -> AppActionPreset? {
        presets.first { $0.combo == shortcut.combo && $0.title == shortcut.title }
    }

    private func apply(_ preset: AppActionPreset) {
        guard let combo = preset.combo else { return }
        shortcut.title = preset.title
        shortcut.combo = combo
        shortcut.symbol = preset.symbol
        shortcut.delivery = preset.delivery
    }
}

// MARK: - Menu Command

/// A command from an app's menu bar, picked from the running app's live menus.
struct MenuItemEditor: View {
    @Binding var item: MenuItemRef
    @Binding var setup: Bool
    @ViewState private var showsBrowser = false

    var body: some View {
        InAppTargetRow(bundleID: item.bundleID, appName: item.appName, setup: $setup) { app in
            item.bundleID = app.bundleID
            item.appName = app.name
            item.path = []
            showsBrowser = true
        }
        LabeledContent("Command") {
            Button {
                showsBrowser = true
            } label: {
                Text(item.path.isEmpty ? "Choose Command…" : item.path.joined(separator: " › "))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .disabled(item.bundleID.isEmpty)
            .popover(isPresented: $showsBrowser, arrowEdge: .leading) {
                MenuCommandBrowser(bundleID: item.bundleID, appName: item.appName, selection: item.path) { path in
                    item.path = path
                    showsBrowser = false
                }
                .frame(width: 360, height: 460)
            }
            .accessibilityLabel("Menu command")
            .accessibilityValue(item.path.isEmpty ? "None chosen" : item.path.joined(separator: ", "))
        }
        DeliveryPicker(delivery: $item.delivery, appName: item.appName)
    }
}

/// Browses the running app's menu bar and returns the chosen command's path.
private struct MenuCommandBrowser: View {
    let bundleID: String
    let appName: String
    let selection: [String]
    let onPick: ([String]) -> Void

    @ViewState private var menus: [MenuNode]?
    @ViewState private var isLoading = true
    @ViewState private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search \(appName)'s menus", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(10)
            Divider()
            content
        }
        .task(id: bundleID) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Reading \(appName)'s menus…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let menus {
            let results = filtered(menus)
            if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(results, children: \.optionalChildren) { node in
                    row(node)
                }
                .listStyle(.sidebar)
            }
        } else {
            ContentUnavailableView {
                Label("Open \(appName)", systemImage: "menubar.rectangle")
            } description: {
                Text(PermissionCenter.shared.status(.accessibility) == .granted
                     ? "Halo reads the menus from the running app. Open \(appName), then try again."
                     : "Halo needs Accessibility permission to read \(appName)'s menus.")
            } actions: {
                Button("Try Again") { Task { await load() } }
            }
        }
    }

    @ViewBuilder
    private func row(_ node: MenuNode) -> some View {
        if node.isCommand {
            Button {
                onPick(node.path)
            } label: {
                HStack {
                    Text(query.isEmpty ? node.title : node.path.joined(separator: " › "))
                        .foregroundStyle(node.isEnabled ? .primary : .secondary)
                    Spacer()
                    if node.path == selection {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                    if let shortcut = node.shortcut {
                        Text(shortcut).foregroundStyle(.secondary).monospaced()
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(node.path.joined(separator: ", "))
        } else {
            Text(node.title).fontWeight(.medium)
        }
    }

    private func load() async {
        isLoading = true
        menus = await MenuBarReader.menus(ofBundleID: bundleID)
        isLoading = false
    }

    /// With a query: matching commands as a flat list (their full path shown); else the tree.
    private func filtered(_ nodes: [MenuNode]) -> [MenuNode] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nodes }
        func commands(_ list: [MenuNode]) -> [MenuNode] {
            list.flatMap { $0.isCommand ? [$0] : commands($0.children) }
        }
        return commands(nodes).filter { $0.path.joined(separator: " ").range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}

private extension MenuNode {
    var optionalChildren: [MenuNode]? { children.isEmpty ? nil : children }
}

// MARK: - Click Buttons

/// Buttons in an app's window clicked in order, by their accessible names (Teams: More actions ›
/// Record › Confirm). Steps can be typed, taken from the app's presets, or picked by pointing.
struct ButtonSequenceEditor: View {
    @Binding var sequence: ButtonSequence
    @Binding var setup: Bool
    /// Seconds left before reading the control under the pointer, while pointing.
    @ViewState private var countdown: Int?
    @ViewState private var pointingNote: String?

    var body: some View {
        InAppTargetRow(bundleID: sequence.bundleID, appName: sequence.appName, setup: $setup) { app in
            sequence.bundleID = app.bundleID
            sequence.appName = app.name
            if sequence.steps.isEmpty, let preset = presets.first { apply(preset) }
        }
        if !presets.isEmpty {
            LabeledContent("Preset") {
                Menu {
                    ForEach(presets) { preset in
                        Button { apply(preset) } label: { Label(preset.title, systemImage: preset.symbol) }
                    }
                } label: {
                    Text(presets.first { $0.title == sequence.title }?.title ?? "Custom")
                }
                .fixedSize()
            }
        }
        CommittingTextField("Name", text: $sequence.title, prompt: "What it does, e.g. Start Recording")

        ForEach(Array(sequence.steps.enumerated()), id: \.element.id) { index, step in
            StepRow(index: index, count: sequence.steps.count, step: stepBinding(step.id),
                    move: { move(step.id, by: $0) }, remove: { sequence.steps.removeAll { $0.id == step.id } })
        }
        HStack {
            Button("Add Step") { sequence.steps.append(ButtonStep(names: [])) }
            Button(countdown.map { "Point at the Button… \($0)" } ?? "Add by Pointing…") { startPointing() }
                .disabled(countdown != nil)
                .help("Gives you 5 seconds to hover over the button (open its menu first if needed); Halo reads its name")
        }
        if let pointingNote {
            Text(pointingNote).font(.caption).foregroundStyle(.secondary)
        }
        Text("Halo finds each button by the name VoiceOver reads. List alternatives separated by commas; an optional step is skipped when it doesn't appear.")
            .font(.caption)
            .foregroundStyle(.secondary)
        DeliveryPicker(delivery: $sequence.delivery, appName: sequence.appName)
    }

    private var presets: [AppActionPreset] {
        AppActionPresets.presets(forBundleID: sequence.bundleID).filter { $0.buttons != nil }
    }

    private func apply(_ preset: AppActionPreset) {
        sequence.title = preset.title
        sequence.steps = (preset.buttons ?? []).map { ButtonStep(names: $0.names, isOptional: $0.isOptional) }
        sequence.symbol = preset.symbol
        sequence.delivery = preset.delivery
    }

    private func stepBinding(_ id: ButtonStep.ID) -> Binding<ButtonStep> {
        Binding(
            get: { sequence.steps.first { $0.id == id } ?? ButtonStep(id: id, names: []) },
            set: { newValue in
                guard let i = sequence.steps.firstIndex(where: { $0.id == id }) else { return }
                sequence.steps[i] = newValue
            }
        )
    }

    private func move(_ id: ButtonStep.ID, by offset: Int) {
        guard let i = sequence.steps.firstIndex(where: { $0.id == id }), sequence.steps.indices.contains(i + offset) else { return }
        sequence.steps.swapAt(i, i + offset)
    }

    /// Counts down, then reads the control under the pointer and adds it as a step.
    private func startPointing() {
        pointingNote = nil
        Task { @MainActor in
            for remaining in stride(from: 5, through: 1, by: -1) {
                countdown = remaining
                try? await Task.sleep(for: .seconds(1))
            }
            countdown = nil
            guard let found = await ButtonActions.controlUnderPointer() else {
                pointingNote = PermissionCenter.shared.status(.accessibility) == .granted
                    ? "No named button was under the pointer. Try hovering right over it."
                    : "Halo needs Accessibility permission to read buttons."
                NSApp.activate()
                return
            }
            if sequence.bundleID.isEmpty {
                sequence.bundleID = found.bundleID
                sequence.appName = found.appName
            }
            if found.bundleID == sequence.bundleID {
                sequence.steps.append(ButtonStep(names: [found.name]))
                pointingNote = "Added “\(found.name)”."
            } else {
                pointingNote = "That button is in \(found.appName), not \(sequence.appName)."
            }
            NSApp.activate()
        }
    }
}

/// One step: its names, optional switch, and move/remove controls.
private struct StepRow: View {
    let index: Int
    let count: Int
    @Binding var step: ButtonStep
    let move: (Int) -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("\(index + 1)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 16)
            CommittingTextField("Step \(index + 1)", text: namesText, prompt: "Button name, e.g. More actions")
                .labelsHidden()
                .help(step.names.joined(separator: ", "))
            Toggle("Optional", isOn: $step.isOptional)
                .toggleStyle(.checkbox)
                .help("Skip this step when the button doesn't appear")
            ControlGroup {
                Button { move(-1) } label: { Image(systemName: "chevron.up") }
                    .disabled(index == 0)
                    .accessibilityLabel("Move step up")
                Button { move(1) } label: { Image(systemName: "chevron.down") }
                    .disabled(index == count - 1)
                    .accessibilityLabel("Move step down")
            }
            .fixedSize()
            Button(role: .destructive, action: remove) { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove step \(index + 1)")
        }
    }

    /// The names as "More actions, More".
    private var namesText: Binding<String> {
        Binding(
            get: { step.names.joined(separator: ", ") },
            set: { text in
                step.names = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            }
        )
    }
}

// MARK: - Shared rows

/// The app an in-app action belongs to, with a picker.
private struct InAppTargetRow: View {
    let bundleID: String
    let appName: String
    @Binding var setup: Bool
    let onPick: (AppInfo) -> Void
    @ViewState private var showsPicker = false

    var body: some View {
        LabeledContent("App") {
            Button {
                showsPicker = true
            } label: {
                HStack(spacing: 6) {
                    if !bundleID.isEmpty {
                        Image(nsImage: AppCatalog.shared.icon(forBundleID: bundleID))
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 18, height: 18)
                            .accessibilityHidden(true)
                    }
                    Text(bundleID.isEmpty ? "Choose App…" : appName)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .popover(isPresented: $showsPicker, arrowEdge: .leading) {
                AppPickerView(selectedBundleID: bundleID) { app in
                    showsPicker = false
                    onPick(app)
                }
                .frame(width: 320, height: 440)
            }
            .accessibilityLabel("App")
            .accessibilityValue(bundleID.isEmpty ? "None chosen" : appName)
        }
        .onChange(of: setup, initial: true) { _, pending in
            guard pending else { return }
            setup = false
            if bundleID.isEmpty { Task { @MainActor in showsPicker = true } }
        }
        if bundleID.isEmpty {
            InspectorNote(.warning, "Choose the app this action is for.")
        }
    }
}

/// Whether Halo returns to the previous app after sending to this one.
private struct DeliveryPicker: View {
    @Binding var delivery: AppDelivery
    let appName: String

    var body: some View {
        Picker("When Chosen", selection: $delivery) {
            Text("Switch to \(appName.isEmpty ? "App" : appName)").tag(AppDelivery.bringToFront)
            Text("Return Afterwards").tag(AppDelivery.bringToFrontAndReturn)
        }
        .pickerStyle(.segmented)
        Text(delivery == .bringToFrontAndReturn
             ? "Works from any app: Halo brings \(appName.isEmpty ? "the app" : appName) forward, does this, then returns you to where you were."
             : "Halo brings \(appName.isEmpty ? "the app" : appName) to the front if it isn't already, then does this.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
