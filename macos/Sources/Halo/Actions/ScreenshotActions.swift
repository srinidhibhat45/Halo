import AppKit
import HaloCore

/// Screenshots through the system's own shortcuts (⇧⌘3, ⇧⌘4 and their ⌃ clipboard variants, as
/// rebound in Keyboard Settings) and Screenshot.app for the toolbar. The capture then runs in the
/// system's screenshot service, so Halo needs only Accessibility, never Screen Recording, and the
/// user's save location, format and thumbnail settings apply.
enum ScreenshotActions {
    private static let toolbarApp = "/System/Applications/Utilities/Screenshot.app"

    static func run(_ options: ScreenshotOptions) async -> ActionOutcome {
        if options.mode == .toolbar { return await openToolbar() }
        if let missing = PermissionCenter.shared.gate(.accessibility) { return missing }

        let hotKey: SymbolicHotKey = switch (options.mode, options.toClipboard) {
        case (.fullScreen, false): .saveScreen
        case (.fullScreen, true): .copyScreen
        case (_, false): .saveArea
        case (_, true): .copyArea
        }
        guard let binding = hotKey.binding else {
            // The user switched the shortcut off; the toolbar still offers every mode.
            let outcome = await openToolbar()
            return outcome == .success ? .successWithMessage("Screenshot shortcut is off, so the toolbar opened") : outcome
        }

        await KeySender.waitForTriggerRelease()
        let pasteboard = Clipboard.changeCount
        let folder = options.mode == .fullScreen && !options.toClipboard ? SaveFolder.current() : nil
        guard await KeySender.press(binding) else { return .failed("Couldn't start the screenshot") }

        switch options.mode {
        case .window:
            // Space switches the crosshair to window picking, but only once the capture UI is up;
            // sent earlier it would type a space into the frontmost app.
            guard await waitForCaptureOverlay() else { return .successWithMessage("Press Space to pick a window") }
            await KeySender.press(CGKeyCode(KeyCode.space), modifiers: [])
            return .success
        case .fullScreen:
            // Confirm only once the capture is done, so the toast can't end up in it.
            if options.toClipboard {
                let copied = await Clipboard.waitForChange(from: pasteboard, timeout: .seconds(2))
                return copied ? .successWithMessage("Copied to clipboard") : .success
            }
            let saved = await folder?.savedMessage()
            return saved.map(ActionOutcome.successWithMessage) ?? .success
        case .area, .toolbar:
            return .success
        }
    }

    private static func openToolbar() async -> ActionOutcome {
        await AppActions.launch(path: toolbarApp, newInstance: true) ? .success : .failed("Couldn't open Screenshot")
    }

    /// Waits up to 1 s for screencaptureui's full-screen selection overlay. Window owners and
    /// bounds are readable without Screen Recording (only titles aren't).
    private static func waitForCaptureOverlay() async -> Bool {
        let screenSizes = NSScreen.screens.map(\.frame.size)
        let deadline = ContinuousClock.now + .seconds(1)
        while ContinuousClock.now < deadline {
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
            let overlayUp = windows.contains { info in
                guard info[kCGWindowOwnerName as String] as? String == "screencaptureui",
                      let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                      let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary) else { return false }
                // The floating thumbnail is small; the selection overlay covers a screen.
                return screenSizes.contains { bounds.width >= $0.width * 0.9 && bounds.height >= $0.height * 0.9 }
            }
            if overlayUp { return true }
            try? await Task.sleep(for: .milliseconds(30))
        }
        return false
    }

    /// Where full-screen captures are saved, to confirm one once its file appears.
    private struct SaveFolder {
        var path: String
        /// The folder's modification date before the capture.
        var modified: Date?

        /// The save folder, or nil when no confirmation should follow: captures don't go to a
        /// file, or macOS shows its floating thumbnail (which confirms the capture itself and
        /// writes the file only once it goes away).
        static func current() -> SaveFolder? {
            let domain = "com.apple.screencapture" as CFString
            CFPreferencesAppSynchronize(domain)
            func value(_ key: String) -> CFPropertyList? { CFPreferencesCopyAppValue(key as CFString, domain) }
            if let target = value("target") as? String, target != "file" { return nil }
            if value("show-thumbnail") as? Bool ?? true { return nil }
            let location = (value("location") as? String)
                .map { ($0 as NSString).expandingTildeInPath }
                .flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
            guard let path = location ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path else {
                return nil
            }
            return SaveFolder(path: path, modified: modificationDate(of: path))
        }

        /// "Saved to Desktop" once the folder changes (a new file), or nil after 2 s.
        func savedMessage() async -> String? {
            let deadline = ContinuousClock.now + .seconds(2)
            while ContinuousClock.now < deadline {
                if Self.modificationDate(of: path) != modified {
                    return "Saved to \(FileManager.default.displayName(atPath: path))"
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            return nil
        }

        private static func modificationDate(of path: String) -> Date? {
            (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        }
    }
}
