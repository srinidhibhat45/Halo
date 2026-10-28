import AppKit
import HaloCore
import SwiftUI

// Owned by the ring-editor engineer. Debug aid: renders the ring editor, the Add to Ring picker
// and the Add App Ring sheet to PNGs (through SnapshotRenderer's Core Animation path) so the UI
// can be reviewed without screen recording. Invoked by `Halo --render-ui <dir>`; the app exits
// afterwards.
//
// Every view edits a staged configuration in a throwaway `AppModel` (saved under
// `<dir>/.render-state/`), never the user's: the default rings with one empty slot, plus a
// Safari ring that fills its empty slots from Everywhere. Animations are off in the staged
// settings, so the editor's build-in never shows mid-flight.
enum UISnapshotRenderer {
    private static let editorSize = CGSize(width: 1040, height: 700)

    static func run(outputDirectory: URL) {
        NSApplication.shared.setActivationPolicy(.prohibited)
        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        } catch {
            Log.app.error("UI snapshots: cannot create \(outputDirectory.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }
        waitForInstalledApps()

        let model = AppModel(fileURL: outputDirectory.appending(path: ".render-state/config.json"))
        model.replaceConfig(with: stagedConfig(), actionName: "Stage Snapshots")
        let safari = model.config.appProfiles.first.map { RingTarget.app($0.id) } ?? .global
        let shot = Shots(directory: outputDirectory, model: model)

        // The editor in its main states.
        shot.editor("editor-overview")
        shot.editor("editor-empty-slot", slot: 4)
        shot.editor("editor-slot-selected", slot: 6)
        shot.editor("editor-library") { $0.showsLibrary = true }
        shot.editor("editor-app-ring", target: safari)
        shot.editor("editor-app-ring-inherited-slot", target: safari, slot: 2)
        shot.editor("editor-nested", path: [5], slot: 1)
        shot.editor("editor-nested-prompt", path: [3], slot: 0)
        shot.editor("editor-dark", slot: 6, dark: true)
        shot.editor("editor-library-dark", dark: true) { $0.showsLibrary = true }
        model.updateSettings("Glass") { $0.theme = .glass }
        shot.editor("editor-glass", slot: 2)
        shot.editor("editor-glass-dark", dark: true)
        model.updateSettings("Classic") { $0.theme = .classic }

        // The Add to Ring picker at popover size.
        shot.picker("picker-browse", title: "Add to Ring", subtitle: "Slot 5 · Bottom")
        shot.picker("picker-search", query: "screen", title: "Add to Ring", subtitle: "Slot 5 · Bottom")
        shot.picker("picker-web", query: "github.com", title: "Add to Ring", subtitle: "Slot 5 · Bottom")
        shot.picker("picker-replace-dark", title: "Replace “Finder”", subtitle: "Slot 7 · Left", dark: true)
        // An app ring: the app's own actions first; and a search across every app's actions.
        let teams = AppCatalog.shared.info(bundleID: "com.microsoft.teams2")
            ?? AppInfo(bundleID: "com.microsoft.teams2", name: "Microsoft Teams", url: URL(fileURLWithPath: "/Applications/Microsoft Teams.app"))
        shot.picker("picker-app-ring-teams", title: "Add to Ring", subtitle: "Microsoft Teams ring · Slot 1 · Top", ringApp: teams)
        shot.picker("picker-search-mute", query: "mute", title: "Add to Ring", subtitle: "Slot 5 · Bottom")

        // The Add App Ring sheet.
        shot.render("add-app-ring", size: AddAppRingSheet.size) { AddAppRingSheet(model: model) { _ in } }
        shot.render("add-app-ring-search", size: AddAppRingSheet.size) { AddAppRingSheet(model: model, query: "no") { _ in } }
    }

    /// Renders views against the staged model into `directory`.
    private struct Shots {
        let directory: URL
        let model: AppModel
        let shortcuts = ShortcutNames(preloaded: ["Log Water", "Resize Images", "Send ETA", "Start Focus Timer", "Translate Clipboard"])

        func editor(_ name: String, target: RingTarget = .global, path: [Int] = [], slot: Int? = nil, dark: Bool = false,
                    configure: (RingEditorSession) -> Void = { _ in }) {
            let session = RingEditorSession(target: target, path: path, slot: slot, model: model, shortcuts: shortcuts)
            session.showsLibrary = false
            session.showsInspector = true
            configure(session)
            render(name, size: editorSize, dark: dark) { RingEditorView(session: session) }
        }

        func picker(_ name: String, query: String = "", title: String, subtitle: String, dark: Bool = false, ringApp: AppInfo? = nil) {
            render(name, size: AddToRingPicker.size, dark: dark) {
                AddToRingPicker(title: title, subtitle: subtitle, recentApps: model.recentApps, shortcuts: shortcuts, ringApp: ringApp, query: query,
                                onChoose: { _ in }, onCancel: {})
            }
        }

        func render(_ name: String, size: CGSize, dark: Bool = false, @ViewBuilder content: () -> some View) {
            // Opaque like the window it sits in, so translucent pixels can't come out wrong.
            // Drawn as the key window, as the user sees it (an off-screen window is inactive).
            let view = content()
                .frame(width: size.width, height: size.height)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.appearsActive, true)
            guard let image = SnapshotRenderer.renderThroughCoreAnimation(view, size: size, dark: dark) else {
                Log.app.error("UI snapshots: \(name, privacy: .public) failed to render")
                return
            }
            SnapshotRenderer.write(image, to: directory.appending(path: name + ".png"))
        }
    }

    /// Lets the installed-apps scan finish (up to 5 s), so app grids aren't empty.
    private static func waitForInstalledApps() {
        let catalog = AppCatalog.shared
        if catalog.installed.isEmpty { catalog.refresh() }
        let deadline = Date().addingTimeInterval(5)
        while catalog.isScanning, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    /// The default configuration, animations off, with the bottom slot empty and a Safari ring
    /// that has two actions of its own and fills the rest from Everywhere.
    private static func stagedConfig() -> HaloConfig {
        var config = HaloConfig.default
        config.settings.animationSpeed = 0
        config.settings.hasCompletedOnboarding = true
        config.globalRing[4] = Slot(id: config.globalRing[4].id)
        var safari = Ring(slotCount: config.globalRing.slotCount)
        safari[1] = Slot(id: safari[1].id, action: .keystroke(KeyCombo(keyCode: KeyCode.t, modifiers: .command, keyLabel: "T")), title: "New Tab",
                         icon: .symbol(name: "plus.square.on.square"))
        safari[3] = Slot(id: safari[3].id, action: .url(WebLink(url: "https://developer.apple.com")), title: "Developer")
        config.appProfiles = [AppProfile(bundleID: "com.apple.Safari", appName: "Safari", ring: safari, inheritsGlobalSlots: true)]
        return config
    }
}
