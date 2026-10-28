import HaloCore
import SwiftUI

/// The configurator's sidebar: the Everywhere ring, the app rings (drag to reorder) with
/// "Add App Ring…", then the settings panes.
struct SettingsSidebar: View {
    @Binding var selection: SettingsSidebarItem?

    @ViewState private var isAddingAppRing = false
    @ViewState private var pendingRemoval: AppProfile?
    @ViewState private var pendingReplacement: AppProfile?

    private var model: AppModel { .shared }

    var body: some View {
        List(selection: $selection) {
            Section("Rings") {
                Label("Everywhere", systemImage: HaloSymbol.ring)
                    .tag(SettingsSidebarItem.ring(.global))
                    .help("The ring for every app without its own")

                ForEach(model.config.appProfiles) { profile in
                    AppRingRow(profile: profile, appRingsEnabled: model.settings.appRingsEnabled)
                        .tag(SettingsSidebarItem.ring(.app(profile.id)))
                        .contextMenu { menu(for: profile) }
                }
                .onMove { source, destination in
                    model.moveAppProfiles(from: source, to: destination)
                }

                Button {
                    isAddingAppRing = true
                } label: {
                    Label("Add App Ring…", systemImage: "plus.circle")
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: .command)
                .help("Add a ring that replaces Everywhere while an app is in front (⌘N)")
            }

            Section("Settings") {
                ForEach(SettingsSidebarItem.panes, id: \.self) { item in
                    Label(item.paneTitle, systemImage: item.paneSymbol)
                        .tag(item)
                }
            }
        }
        .listStyle(.sidebar)
        .onDeleteCommand {
            if case .ring(.app(let id))? = selection { pendingRemoval = model.profile(id) }
        }
        .sheet(isPresented: $isAddingAppRing) {
            AddAppRingSheet { id in selection = .ring(.app(id)) }
        }
        .confirmationDialog(
            pendingRemoval.map { "Remove the \($0.appName) ring?" } ?? "",
            isPresented: Binding(isPresenting: $pendingRemoval),
            presenting: pendingRemoval
        ) { profile in
            Button("Remove Ring", role: .destructive) { remove(profile) }
        } message: { profile in
            Text("Halo will show the Everywhere ring in \(profile.appName).")
        }
        .confirmationDialog(
            pendingReplacement.map { "Replace the \($0.appName) ring?" } ?? "",
            isPresented: Binding(isPresenting: $pendingReplacement),
            presenting: pendingReplacement
        ) { profile in
            Button("Replace with Copy") { replaceWithGlobalCopy(profile) }
        } message: { profile in
            Text("The actions in the \(profile.appName) ring will be replaced with a copy of the Everywhere ring.")
        }
    }

    @ViewBuilder
    private func menu(for profile: AppProfile) -> some View {
        Button(profile.isEnabled ? "Disable" : "Enable", systemImage: profile.isEnabled ? "pause.circle" : "play.circle") {
            let verb = profile.isEnabled ? "Disable" : "Enable"
            model.updateProfile(profile.id, "\(verb) \(profile.appName) Ring") { $0.isEnabled.toggle() }
        }
        if !model.settings.appRingsEnabled {
            Button("Turn On App Rings", systemImage: "checkmark.circle") {
                model.updateSettings("Turn On App Rings") { $0.appRingsEnabled = true }
            }
        }
        Button("Replace with Copy of Everywhere Ring", systemImage: "square.on.square") {
            if profile.ring.isEmpty {
                replaceWithGlobalCopy(profile)
            } else {
                pendingReplacement = profile
            }
        }
        Divider()
        Button("Remove…", systemImage: "trash", role: .destructive) {
            pendingRemoval = profile
        }
    }

    private func remove(_ profile: AppProfile) {
        if selection == .ring(.app(profile.id)) { selection = .ring(.global) }
        model.removeAppProfile(profile.id)
    }

    private func replaceWithGlobalCopy(_ profile: AppProfile) {
        let copy = AppModel.freshIDs(model.config.globalRing)
        model.updateProfile(profile.id, "Replace \(profile.appName) Ring") { profile in
            profile.ring = copy
            profile.inheritsGlobalSlots = false
        }
        selection = .ring(.app(profile.id))
    }
}

/// An app ring in the sidebar: app icon and name, dimmed with an "Off" badge when the ring
/// isn't used (disabled, or app rings turned off in General).
private struct AppRingRow: View {
    let profile: AppProfile
    let appRingsEnabled: Bool

    private var isActive: Bool { profile.isEnabled && appRingsEnabled }

    var body: some View {
        Label {
            Text(profile.appName)
                .foregroundStyle(isActive ? .primary : .secondary)
        } icon: {
            Image(nsImage: AppCatalog.shared.icon(forBundleID: profile.bundleID))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
                .saturation(isActive ? 1 : 0)
                .opacity(isActive ? 1 : 0.6)
        }
        .badge(isActive ? nil : Text("Off"))
        .help(helpText)
        .accessibilityLabel("\(profile.appName) ring")
        .accessibilityValue(isActive ? "On" : "Off")
        .accessibilityHint("Drag to reorder. Open the context menu to enable, copy or remove.")
    }

    private var helpText: String {
        if !profile.isEnabled { return "Off: Everywhere is shown in \(profile.appName)" }
        if !appRingsEnabled { return "App rings are turned off in General" }
        return "Shown while \(profile.appName) is in front"
    }
}
