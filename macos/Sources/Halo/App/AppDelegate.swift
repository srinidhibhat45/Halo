import AppKit
import HaloCore

/// App lifecycle: one running copy, accessory activation, wiring settings changes to the overlay
/// and the login item, first-run onboarding, config problems, and saving on quit.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Posted (distributed) by a second copy of Halo to ask the running one to show its settings.
    private static let showSettingsRequest = Notification.Name("com.srinidhibhat.Halo.showSettings")

    /// True when this process found another Halo running and is quitting in its favour.
    private var isHandingOff = false
    /// True while the login-item setting is being made to match macOS, so that change isn't
    /// pushed back to macOS.
    private var isAdoptingLoginItemState = false
    private var showSettingsObserver: NSObjectProtocol?

    // MARK: Launch and quit

    func applicationDidFinishLaunching(_ notification: Notification) {
        if handOffToRunningInstance() { return }

        // LSUIElement already makes Halo an accessory; this covers running the bare executable.
        NSApp.setActivationPolicy(.accessory)
        if InstallLocation.offerMoveIfNeeded() {
            isHandingOff = true   // quitting for the moved copy: nothing to save yet
            NSApp.terminate(nil)
            return
        }
        MainMenu.install()
        listenForShowSettingsRequests()

        let model = AppModel.shared
        model.settingsDidChange = { [weak self] old, new in
            OverlayController.shared.settingsChanged(new)
            if old.launchAtLogin != new.launchAtLogin { self?.applyLaunchAtLogin(new.launchAtLogin) }
            if old.checksForUpdates != new.checksForUpdates { UpdateController.shared.settingsChanged(new) }
        }
        adoptLoginItemState(ifUnavailable: nil)

        OverlayController.shared.start()
        AppCatalog.shared.refresh()
        PermissionCenter.shared.refresh()
        UpdateController.shared.start()
        Log.permissions.notice("Accessibility at launch: \(PermissionCenter.shared.status(.accessibility) == .granted ? "granted" : "not granted", privacy: .public)")

        if !model.settings.hasCompletedOnboarding {
            WindowCoordinator.shared.show(.onboarding)
        }
        reportConfigProblemIfNeeded()
        Log.app.info("Halo launched")
    }

    /// Ends text editing first so fields that commit on blur save their drafts, then quits on
    /// the next run-loop turn (after SwiftUI has processed the focus change).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isHandingOff, NSApp.windows.contains(where: { $0.isVisible && $0.firstResponder is NSText }) else { return .terminateNow }
        for window in NSApp.windows where window.isVisible { window.makeFirstResponder(nil) }
        DispatchQueue.main.async { NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !isHandingOff else { return }
        AppModel.shared.flush()
    }

    /// Opening Halo again (Finder, Spotlight, the Dock) shows its windows. This is how settings
    /// stay reachable when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if WindowCoordinator.shared.isVisible(.onboarding) {
            WindowCoordinator.shared.show(.onboarding)
        } else {
            SettingsRouter.shared.open()
        }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        MainMenu.install()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: Single instance

    /// If another copy of Halo is running, asks it to show its settings and quits this one.
    private func handOffToRunningInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let other = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first(where: { $0.processIdentifier != ownPID && !$0.isTerminated })
        else { return false }

        Log.app.info("Halo is already running (pid \(other.processIdentifier)); handing over")
        isHandingOff = true
        // Lets the running copy bring its settings window forward.
        NSApp.yieldActivation(to: other)
        DistributedNotificationCenter.default().postNotificationName(
            Self.showSettingsRequest, object: bundleID, userInfo: nil, deliverImmediately: true
        )
        NSApp.terminate(nil)
        return true
    }

    private func listenForShowSettingsRequests() {
        showSettingsObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.showSettingsRequest, object: Bundle.main.bundleIdentifier, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                Log.app.info("Another copy of Halo asked to show settings")
                SettingsRouter.shared.open()
            }
        }
    }

    // MARK: Launch at login

    /// Makes the setting match the login item's real state, without an undo step: the user may
    /// have changed it in System Settings › General › Login Items, or registration may have
    /// failed. `fallback` is used when login items are unavailable; nil leaves the setting alone.
    private func adoptLoginItemState(ifUnavailable fallback: Bool?) {
        let registered: Bool
        switch LaunchAtLogin.status {
        case .enabled, .requiresApproval: registered = true
        case .disabled: registered = false
        case .unavailable:
            guard let fallback else { return }
            registered = fallback
        }
        guard AppModel.shared.settings.launchAtLogin != registered else { return }
        isAdoptingLoginItemState = true
        defer { isAdoptingLoginItemState = false }
        AppModel.shared.updateSettingsOutsideUndo { $0.launchAtLogin = registered }
    }

    /// Pushes a changed setting to macOS. A pending approval is shown next to the switches
    /// (General pane, welcome guide); a failure gets an alert and the setting is put back.
    private func applyLaunchAtLogin(_ enabled: Bool) {
        guard !isAdoptingLoginItemState else { return }
        do {
            try LaunchAtLogin.setEnabled(enabled)
        } catch {
            // The alert and the corrective setting change wait until the current update (often a
            // SwiftUI toggle) has finished.
            Task {
                adoptLoginItemState(ifUnavailable: false)
                await reportLoginItemFailure(error)
            }
        }
    }

    private func reportLoginItemFailure(_ error: Error) async {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't Change Launch at Login"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Login Items Settings")
        if await present(alert) == .alertSecondButtonReturn {
            LaunchAtLogin.openLoginItemsSettings()
        }
    }

    // MARK: Config problems

    /// Tells the user, once per launch, when the saved configuration couldn't be read.
    private func reportConfigProblemIfNeeded() {
        let title: String
        let details: String
        let file: URL
        switch AppModel.shared.loadOutcome {
        case .loaded, .createdDefault:
            return
        case .recoveredFromCorruption(let movedTo):
            title = "Halo Couldn't Read Its Settings"
            details = "The configuration file was damaged, so Halo set it aside as “\(movedTo.lastPathComponent)” and started from your most recent backup, or from the default ring if there was none."
            file = movedTo
        case .unreadable(let reason):
            title = "Halo Can't Open Its Settings File"
            details = "Halo is using the default ring for now and won't save changes, so the file stays exactly as it is.\n\n\(reason)"
            file = ConfigFile.defaultURL
        }
        Task {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = title
            alert.informativeText = details
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Show in Finder")
            if await present(alert) == .alertSecondButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([file])
            }
        }
    }

    // MARK: Alerts

    /// Shows `alert` as a sheet on Halo's key window, or as a standalone alert when none is open.
    private func present(_ alert: NSAlert) async -> NSApplication.ModalResponse {
        if let window = NSApp.keyWindow, window.isVisible, !(window is NSPanel), window.attachedSheet == nil {
            return await alert.beginSheetModal(for: window)
        }
        NSApp.activate()
        return alert.runModal()
    }
}

extension AppModel {
    /// Changes settings without an undo step, for bookkeeping the user didn't do in the
    /// configurator (finishing the welcome guide, matching the login item's real state).
    func updateSettingsOutsideUndo(_ body: (inout AppSettings) -> Void) {
        undoManager.disableUndoRegistration()
        defer { undoManager.enableUndoRegistration() }
        updateSettings("Change Setting", body)
    }
}
