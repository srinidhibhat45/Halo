import AppKit
import HaloCore
import HaloShims

/// Apps, links and files, through Launch Services (no permission needed).
enum AppActions {
    // MARK: Apps

    static func run(_ target: AppTarget) async -> ActionOutcome {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleID).filter { !$0.isTerminated }
        switch target.behavior {
        case .quit:
            return quit(running, name: target.name)
        case .toggle where running.contains(where: \.isFrontmost):
            return running.map { $0.hide() }.contains(true) ? .success : .failed("Couldn't hide \(target.name)")
        case .open, .toggle:
            guard let url = running.first?.bundleURL ?? applicationURL(for: target) else {
                return .failed("\(target.name) isn't installed")
            }
            return await open(appAt: url, name: target.name, wasRunning: running.first)
        }
    }

    private static func applicationURL(for target: AppTarget) -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleID) { return url }
        guard let path = target.path, FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Launches or focuses the app like a Dock click (a running app with no windows opens one),
    /// and returns once it is in front, so whatever comes next (a Smart Action's keystroke)
    /// reaches it rather than the app that was in front before.
    private static func open(appAt url: URL, name: String, wasRunning: NSRunningApplication?) async -> ActionOutcome {
        if let wasRunning, wasRunning.isHidden { wasRunning.unhide() }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        do {
            let app = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            // A fresh launch activates itself once it finishes launching, so give it time; an
            // app that was already running can be left behind by cooperative activation.
            await bringToFront(app, patience: wasRunning == nil ? .milliseconds(1700) : .milliseconds(400))
            return .success
        } catch {
            Log.actions.error("Open \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return .failed("Couldn't open \(name)")
        }
    }

    /// Waits `patience` for `app` to come to the front by itself. macOS 14+ may refuse activation
    /// requested by a background agent, so if it didn't, falls back to SetFrontProcessWithOptions
    /// (through the C shim), then to a plain activation request.
    static func bringToFront(_ app: NSRunningApplication, patience: Duration) async {
        if await waitUntilFrontmost(app, timeout: patience) { return }
        let status = halo_set_front_process(app.processIdentifier)
        if status != 0 { Log.actions.notice("SetFrontProcess returned \(status)") }
        if await waitUntilFrontmost(app, timeout: .milliseconds(300)) { return }
        _ = app.activate(options: [.activateAllWindows])
    }

    private static func waitUntilFrontmost(_ app: NSRunningApplication, timeout: Duration) async -> Bool {
        await waitUntil(timeout: timeout) { app.isFrontmost }
    }

    /// True once an app with `bundleID` is frontmost, waiting at most `timeout`.
    static func waitUntilFrontmost(bundleID: String, timeout: Duration) async -> Bool {
        await waitUntil(timeout: timeout) { isFrontmost(bundleID: bundleID) }
    }

    static func isFrontmost(bundleID: String) -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
    }

    private static func waitUntil(timeout: Duration, _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return condition()
    }

    private static func quit(_ running: [NSRunningApplication], name: String) -> ActionOutcome {
        guard !running.isEmpty else { return .successWithMessage("\(name) isn't running") }
        // terminate() is a normal quit: the app may still ask to save documents.
        return running.map { $0.terminate() }.contains(true) ? .success : .failed("Couldn't quit \(name)")
    }

    /// Opens a system helper app (launchers such as Apps, Siri, Screenshot). `newInstance` makes
    /// a launcher that is still running run again instead of just being activated.
    static func launch(path: String, newInstance: Bool = false, activates: Bool = true) async -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activates
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = newInstance
        do {
            _ = try await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: configuration)
            return true
        } catch {
            Log.actions.error("Launch \(path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: Links

    static func open(_ link: WebLink) async -> ActionOutcome {
        guard let url = normalizedURL(link.url) else { return .failed("That link isn't valid") }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            if let bundleID = link.openWithBundleID, !bundleID.isEmpty {
                guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                    return .failed("The app chosen for this link isn't installed")
                }
                _ = try await NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
            } else {
                guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
                    return .failed("No app can open \(url.scheme ?? "these") links")
                }
                _ = try await NSWorkspace.shared.open(url, configuration: configuration)
            }
            return .success
        } catch {
            Log.actions.error("Open link failed: \(error.localizedDescription, privacy: .public)")
            return .failed("Couldn't open the link")
        }
    }

    /// Accepts full URLs, deep links, bare domains ("apple.com") and paths.
    static func normalizedURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
        }
        if let url = URL(string: trimmed), let scheme = url.scheme, !scheme.isEmpty {
            return url
        }
        if trimmed.contains("."), !trimmed.contains(" ") { return URL(string: "https://" + trimmed) }
        return nil
    }

    // MARK: Files

    static func open(_ file: FileTarget) async -> ActionOutcome {
        let path = file.expandedPath
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
            return .failed("“\(file.displayName)” wasn't found")
        }
        let url = URL(fileURLWithPath: path)
        if file.revealInFinder {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return .success
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.open(url, configuration: configuration)
            return .success
        } catch {
            Log.actions.error("Open file failed: \(error.localizedDescription, privacy: .public)")
            return .failed("Couldn't open “\(file.displayName)”")
        }
    }
}

private extension NSRunningApplication {
    var isFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == processIdentifier
    }
}
