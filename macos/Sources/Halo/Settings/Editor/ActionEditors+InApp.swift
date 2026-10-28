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

        let presets = AppActionPresets.presets(forBundleID: shortcut.bundleID)
        if !presets.isEmpty {
            LabeledContent("Preset") {
                Menu {
                    ForEach(presets) { preset in
                        Button {
                            apply(preset)
                        } label: {
                            Label("\(preset.title)  \(preset.combo.displayString)", systemImage: preset.symbol)
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
        shortcut.title = preset.title
        shortcut.combo = preset.combo
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
             ? "Works from any app: Halo brings \(appName.isEmpty ? "the app" : appName) forward, sends it, then returns you to where you were."
             : "Halo brings \(appName.isEmpty ? "the app" : appName) to the front if it isn't already, then sends it.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
