import HaloCore
import SwiftUI

/// A row of the configurator's sidebar: a ring to edit or a settings pane.
enum SettingsSidebarItem: Hashable {
    case ring(RingTarget)
    case general
    case appearance
    case permissions
    case about

    /// The settings panes, in sidebar order.
    static let panes: [SettingsSidebarItem] = [.general, .appearance, .permissions, .about]

    init(_ destination: SettingsDestination) {
        switch destination {
        case .ring(let target, _, _): self = .ring(target)
        case .general: self = .general
        case .appearance: self = .appearance
        case .permissions: self = .permissions
        case .about: self = .about
        }
    }

    /// The router destination that shows this item (rings open at their root).
    var destination: SettingsDestination {
        switch self {
        case .ring(let target): .ring(target)
        case .general: .general
        case .appearance: .appearance
        case .permissions: .permissions
        case .about: .about
        }
    }

    /// Pane title (rings are titled by their app; see `SettingsWindow.title`).
    var paneTitle: String {
        switch self {
        case .ring: "Ring"
        case .general: "General"
        case .appearance: "Appearance"
        case .permissions: "Permissions"
        case .about: "About Halo"
        }
    }

    var paneSymbol: String {
        switch self {
        case .ring: HaloSymbol.ring
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .permissions: "lock.shield"
        case .about: "info.circle"
        }
    }

    /// A stable string for remembering the selection between launches.
    var storageKey: String {
        switch self {
        case .ring(.global): "ring.global"
        case .ring(.app(let id)): "ring.app." + id.uuidString
        case .general: "general"
        case .appearance: "appearance"
        case .permissions: "permissions"
        case .about: "about"
        }
    }

    init?(storageKey: String) {
        switch storageKey {
        case "ring.global": self = .ring(.global)
        case "general": self = .general
        case "appearance": self = .appearance
        case "permissions": self = .permissions
        case "about": self = .about
        default:
            let prefix = "ring.app."
            guard storageKey.hasPrefix(prefix), let id = UUID(uuidString: String(storageKey.dropFirst(prefix.count))) else { return nil }
            self = .ring(.app(id))
        }
    }
}

/// Root view of the configurator window: sidebar (rings + settings panes) and detail.
///
/// Follows `SettingsRouter.shared`: every request (menu, overlay ⌘-click, onboarding) selects
/// its destination, and a request for a nested ring or a slot reopens the ring editor there.
/// The selection is written back to the router, so a plain `open()` keeps the current pane,
/// and remembered across launches.
struct SettingsWindow: View {
    @AppStorage("SettingsWindow.selection") private var storedSelection = SettingsSidebarItem.ring(.global).storageKey
    @ViewState private var selection: SettingsSidebarItem? = .ring(.global)
    @ViewState private var editorEntry = EditorEntry(target: .global)

    /// The first window of a launch restores the remembered selection; later ones follow the router.
    private static var hasRestoredSelection = false

    private var router: SettingsRouter { .shared }
    private var model: AppModel { .shared }

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            detail
                .navigationTitle(title)
                .navigationSubtitle(subtitle)
        }
        .frame(minWidth: 980, minHeight: 640)
        .onAppear(perform: restoreSelection)
        .onChange(of: RouterRequest(destination: router.destination, count: router.requestCount)) { _, request in
            open(request.destination)
        }
        .onChange(of: selection) { _, newValue in
            guard let newValue else { return }
            storedSelection = newValue.storageKey
            // A deep link's folder and slot apply only until the user picks something else.
            if newValue != .ring(editorEntry.target) {
                editorEntry = EditorEntry(target: editorEntry.target, generation: editorEntry.generation)
            }
            if SettingsSidebarItem(router.destination) != newValue {
                router.destination = newValue.destination
            }
        }
        .onChange(of: model.config.appProfiles.map(\.id)) { _, ids in
            if case .ring(.app(let id))? = selection, !ids.contains(id) {
                selection = .ring(.global)
            }
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .ring(let target)?:
            let entry = editorEntry.target == target ? editorEntry : EditorEntry(target: target)
            RingEditorView(target: target, initialPath: entry.path, initialSlot: entry.slot)
                .id(EditorIdentity(target: target, generation: entry.generation))
        case .general?:
            GeneralPane()
        case .appearance?:
            AppearancePane()
        case .permissions?:
            PermissionsPane()
        case .about?:
            AboutPane()
        case nil:
            ContentUnavailableView {
                Label("Nothing Selected", systemImage: HaloSymbol.ring)
            } description: {
                Text("Choose a ring or a settings pane in the sidebar.")
            }
        }
    }

    /// The window title follows the selection.
    private var title: String {
        switch selection {
        case .ring(.global)?: "Everywhere"
        case .ring(.app(let id))?: model.profile(id)?.appName ?? "App Ring"
        case let item?: item.paneTitle
        case nil: "Halo Settings"
        }
    }

    private var subtitle: String {
        switch selection {
        case .ring(.global)?:
            return "The ring for every app without its own"
        case .ring(.app(let id))?:
            guard let profile = model.profile(id) else { return "" }
            if !model.settings.appRingsEnabled { return "App rings are turned off in General" }
            return profile.isEnabled ? "Shown while \(profile.appName) is in front" : "Off: Everywhere is shown instead"
        default:
            return ""
        }
    }

    // MARK: Routing

    private func restoreSelection() {
        defer { Self.hasRestoredSelection = true }
        if !Self.hasRestoredSelection,
           !router.lastRequestNamedDestination,
           let stored = SettingsSidebarItem(storageKey: storedSelection),
           exists(stored) {
            selection = stored
        } else {
            open(router.destination)
        }
    }

    /// Shows `destination`. Ring requests with a folder path or slot reset the editor there.
    private func open(_ destination: SettingsDestination) {
        let item = SettingsSidebarItem(destination)
        guard exists(item) else {
            selection = .ring(.global)
            return
        }
        if case .ring(let target, let path, let slot) = destination, !path.isEmpty || slot != nil {
            editorEntry = EditorEntry(target: target, path: path, slot: slot, generation: editorEntry.generation + 1)
            // Handled: a later plain `open()` should keep the editor where the user left it.
            router.destination = item.destination
        }
        if selection != item { selection = item }
    }

    /// False for an app ring that no longer exists (removed, undone, imported over).
    private func exists(_ item: SettingsSidebarItem) -> Bool {
        if case .ring(.app(let id)) = item { return model.profile(id) != nil }
        return true
    }
}

/// Where the ring editor opens: a folder path and slot from a deep link, for one ring.
private struct EditorEntry: Equatable {
    var target: RingTarget
    var path: [Int] = []
    var slot: Int?
    /// Bumped by every deep link with a path or slot, so the editor resets even when the ring
    /// stays the same.
    var generation = 0
}

/// The ring editor's identity: a new ring, or a new deep link, starts a fresh editor.
private struct EditorIdentity: Hashable {
    var target: RingTarget
    var generation: Int
}

/// One router request, observed as a whole so a request that sets both fields reacts once.
private struct RouterRequest: Equatable {
    var destination: SettingsDestination
    var count: Int
}
