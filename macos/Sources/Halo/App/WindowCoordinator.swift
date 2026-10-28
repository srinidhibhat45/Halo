import AppKit
import SwiftUI

/// Creates and shows Halo's windows: AppKit `NSWindow`s hosting SwiftUI, so they open reliably
/// from the menu bar, the overlay and the app delegate even though Halo is an LSUIElement app.
///
/// While any of them is open Halo runs as a regular app (Dock icon, ⌘-Tab, main menu); when the
/// last one closes it goes back to being an accessory.
final class WindowCoordinator {
    static let shared = WindowCoordinator()

    enum Kind { case settings, onboarding }

    private static let settingsAutosaveName = "HaloSettings"
    private static let settingsMinSize = CGSize(width: 980, height: 640)
    private static let settingsDefaultSize = CGSize(width: 1180, height: 760)

    private var windows: [Kind: NSWindow] = [:]
    /// Delegates live as long as their windows (`NSWindow.delegate` is weak).
    private var delegates: [Kind: WindowEvents] = [:]

    private init() {}

    /// Shows the window and brings Halo forward. An open window comes to the front (and out of the
    /// Dock if minimised) instead of being duplicated.
    func show(_ kind: Kind) {
        let window = windows[kind] ?? open(kind)
        updateActivationPolicy()
        if NSApp.isHidden { NSApp.unhide(nil) }
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // Activation is only a request; make sure the window is on screen even if it was declined.
        window.orderFrontRegardless()
    }

    func close(_ kind: Kind) {
        windows[kind]?.close()
    }

    /// True while the window is open, including while it is minimised or Halo is hidden.
    func isVisible(_ kind: Kind) -> Bool {
        windows[kind] != nil
    }

    // MARK: Window lifecycle

    private func open(_ kind: Kind) -> NSWindow {
        let window = switch kind {
        case .settings: makeSettingsWindow()
        case .onboarding: makeOnboardingWindow()
        }
        let events = WindowEvents(kind: kind)
        window.delegate = events
        windows[kind] = window
        delegates[kind] = events
        Log.app.info("Opened \(String(describing: kind), privacy: .public) window")
        return window
    }

    fileprivate func windowWillClose(_ kind: Kind) {
        // AppKit is still closing the window: keep it and its delegate alive until the next turn
        // of the run loop, then drop them and, if nothing else is open, become an accessory again.
        // Deferring also keeps the Dock icon steady when one window closes as another opens.
        let closing = (windows.removeValue(forKey: kind), delegates.removeValue(forKey: kind))
        if kind == .onboarding { OnboardingFlow.windowDidClose() }
        Task { @MainActor in
            withExtendedLifetime(closing) {}
            self.updateActivationPolicy()
        }
    }

    private func updateActivationPolicy() {
        let policy: NSApplication.ActivationPolicy = windows.isEmpty ? .accessory : .regular
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        if policy == .regular { MainMenu.install() }
    }

    // MARK: Window factories

    private func makeSettingsWindow() -> NSWindow {
        let host = NSHostingController(rootView: SettingsWindow())
        // SwiftUI's `.toolbar` and `.navigationTitle` drive the window's toolbar and title.
        host.sceneBridgingOptions = [.toolbars, .title]
        // SwiftUI sets the minimum size only; the user sizes the window freely above it.
        host.sizingOptions = [.minSize]

        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.title = "Halo Settings"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.contentMinSize = Self.settingsMinSize
        window.setContentSize(Self.settingsDefaultSize)
        window.center()
        // Restores the last frame if there is one (otherwise it stays centred), then keeps saving it.
        window.setFrameUsingName(Self.settingsAutosaveName)
        window.setFrameAutosaveName(Self.settingsAutosaveName)
        return window
    }

    private func makeOnboardingWindow() -> NSWindow {
        let host = NSHostingController(rootView: OnboardingView())
        host.sizingOptions = []

        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Welcome to Halo"
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.setContentSize(OnboardingView.preferredSize)
        window.center()
        return window
    }
}

/// One window's delegate: close bookkeeping, permission refresh, and the shared undo manager.
private final class WindowEvents: NSObject, NSWindowDelegate {
    let kind: WindowCoordinator.Kind

    init(kind: WindowCoordinator.Kind) {
        self.kind = kind
    }

    func windowWillClose(_ notification: Notification) {
        WindowCoordinator.shared.windowWillClose(kind)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // The user may have granted a permission in System Settings while Halo was in the back.
        PermissionCenter.shared.refresh()
        MainMenu.install()
    }

    /// Edits made in Halo's windows (and ⌘Z in their text fields) share the config's undo history.
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        AppModel.shared.undoManager
    }
}
