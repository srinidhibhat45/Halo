import AppKit
import HaloCore
import SwiftUI

/// Halo's entry point. The only SwiftUI scene is the menu bar extra; the lifecycle, the overlay
/// and the windows are AppKit-managed (`AppDelegate`, `WindowCoordinator`).
@main
struct HaloApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Debug: `Halo --render-snapshots <dir>` renders ring PNGs and exits before anything
        // global (hotkeys, menu bar) is set up.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-snapshots") {
            let dir = args.indices.contains(i + 1) ? args[i + 1] : "snapshots"
            SnapshotRenderer.run(outputDirectory: URL(fileURLWithPath: dir))
            exit(0)
        }
        // Debug: `Halo --render-ui <dir>` renders configurator screens and exits.
        if let i = args.firstIndex(of: "--render-ui") {
            let dir = args.indices.contains(i + 1) ? args[i + 1] : "ui-snapshots"
            UISnapshotRenderer.run(outputDirectory: URL(fileURLWithPath: dir))
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra(isInserted: showsMenuBarIcon) {
            MenuBarContent()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.menu)
    }

    /// Whether the icon is in the menu bar. Stored in the config (so it is undoable and travels
    /// with exports); ⌘-dragging the icon out of the menu bar turns it off too.
    private var showsMenuBarIcon: Binding<Bool> {
        Binding(
            get: { AppModel.shared.settings.showMenuBarIcon },
            set: { show in
                AppModel.shared.updateSettings(show ? "Show Menu Bar Icon" : "Hide Menu Bar Icon") {
                    $0.showMenuBarIcon = show
                }
            }
        )
    }
}
