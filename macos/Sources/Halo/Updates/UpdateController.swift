import AppKit
import HaloCore
import Observation

/// Over-the-air updates from GitHub Releases (github.com/srinidhibhat45/Halo).
///
/// Checks shortly after launch and then about once a day (when `checksForUpdates` is on), or
/// when the user asks. A newer stable release with a macOS payload is offered in an alert with
/// its release notes; installing downloads and verifies it (`UpdateInstaller`), quits, swaps the
/// app and relaunches. The first launch after an update helps the user turn Accessibility back
/// on, which macOS drops for apps without a stable developer signature.
@Observable
final class UpdateController {
    static let shared = UpdateController()

    static let repository = "srinidhibhat45/Halo"
    static let releasesPage = URL(string: "https://github.com/\(repository)/releases")

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(SemanticVersion)
        case downloading(SemanticVersion)
        case installing(SemanticVersion)
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var lastChecked: Date?

    @ObservationIgnored private var release: GitHubRelease?
    @ObservationIgnored private var timer: Timer?

    private static let lastCheckedKey = "Updates.lastChecked"
    private static let skippedKey = "Updates.skippedVersion"
    private static let lastLaunchedKey = "Updates.lastLaunchedVersion"
    /// Automatic checks happen at most this often.
    private static let checkInterval: TimeInterval = 20 * 3600

    private init() {
        lastChecked = UserDefaults.standard.object(forKey: Self.lastCheckedKey) as? Date
    }

    /// The running version, or nil for development builds (no version in Info.plist).
    var currentVersion: SemanticVersion? {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(SemanticVersion.init)
    }

    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing: true
        default: false
        }
    }

    /// The version waiting to be installed, if any.
    var availableVersion: SemanticVersion? {
        if case .available(let version) = state { version } else { nil }
    }

    // MARK: Scheduling

    /// Called at launch: notes an update that just happened and starts automatic checks.
    func start() {
        handleFirstLaunchAfterUpdate()
        settingsChanged(AppModel.shared.settings)
    }

    func settingsChanged(_ settings: AppSettings) {
        timer?.invalidate()
        timer = nil
        guard settings.checksForUpdates, currentVersion != nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            MainActor.assumeIsolated { _ = Task { await UpdateController.shared.checkIfDue() } }
        }
        Task {
            try? await Task.sleep(for: .seconds(20))
            await checkIfDue()
        }
    }

    private func checkIfDue() async {
        guard AppModel.shared.settings.checksForUpdates else { return }
        if let lastChecked, Date().timeIntervalSince(lastChecked) < Self.checkInterval { return }
        await check(userInitiated: false)
    }

    // MARK: Checking

    /// Looks for a newer release. User-initiated checks also report "up to date" and errors,
    /// and offer versions the user skipped before.
    func check(userInitiated: Bool) async {
        guard !isBusy else { return }
        guard let current = currentVersion else {
            if userInitiated { inform("Updates are available in the installed app", "This is a development build without a version number.") }
            return
        }
        state = .checking
        do {
            let latest = try await Self.fetchLatestRelease(current: current)
            lastChecked = Date()
            UserDefaults.standard.set(lastChecked, forKey: Self.lastCheckedKey)
            guard let latest else {
                state = .upToDate
                if userInitiated { inform("Halo is up to date", "You have version \(current).") }
                return
            }
            let skipped = userInitiated ? nil : UserDefaults.standard.string(forKey: Self.skippedKey)
            switch UpdatePolicy.evaluate(latest, current: current, skipped: skipped) {
            case .available(let version):
                release = latest
                state = .available(version)
                offer(latest, version: version, current: current)
            case .upToDate, .skipped, .notInstallable:
                state = .upToDate
                if userInitiated { inform("Halo is up to date", "You have version \(current).") }
            }
        } catch {
            Log.app.error("Update check failed: \(error.localizedDescription, privacy: .public)")
            state = userInitiated ? .failed(error.localizedDescription) : .idle
            if userInitiated { inform("Couldn't check for updates", error.localizedDescription) }
        }
    }

    /// The latest release, or nil when the repository has none yet.
    private static func fetchLatestRelease(current: SemanticVersion) async throws -> GitHubRelease? {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Halo/\(current) (macOS)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        guard status == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    // MARK: Installing

    /// Downloads, verifies and installs the available update, then relaunches.
    func installAvailableUpdate() async {
        guard let release, let version = release.version,
              let archive = release.macUpdateArchive, let checksum = release.macUpdateChecksum,
              let bundleID = Bundle.main.bundleIdentifier else { return }
        state = .downloading(version)
        ToastPresenter.shared.show("Downloading Halo \(version)…", symbol: "arrow.down.circle", style: .info, duration: 3)
        do {
            let app = try await UpdateInstaller.prepare(archive: archive.downloadURL, checksum: checksum.downloadURL,
                                                        version: version, bundleIdentifier: bundleID)
            state = .installing(version)
            try UpdateInstaller.scheduleReplacement(of: Bundle.main.bundleURL, with: app, afterExitOf: ProcessInfo.processInfo.processIdentifier)
            Log.app.info("Installing Halo \(version, privacy: .public); relaunching")
            AppModel.shared.flush()
            NSApp.terminate(nil)
        } catch UpdateInstaller.Failure.notWritable(let folder) {
            state = .available(version)
            let alert = NSAlert()
            alert.messageText = "Install Halo \(version) by hand"
            alert.informativeText = "Halo can't replace itself in \(folder.path). Download the installer, quit Halo, and drag the new Halo into that folder."
            alert.addButton(withTitle: "Download Installer")
            alert.addButton(withTitle: "Cancel")
            if run(alert) == .alertFirstButtonReturn, let url = release.macInstaller?.downloadURL ?? Optional(release.pageURL) {
                NSWorkspace.shared.open(url)
            }
        } catch {
            Log.app.error("Update failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
            inform("Halo \(version) couldn't be installed", error.localizedDescription)
        }
    }

    // MARK: Prompts

    private func offer(_ release: GitHubRelease, version: SemanticVersion, current: SemanticVersion) {
        let alert = NSAlert()
        alert.messageText = "Halo \(version) is available"
        alert.informativeText = "You have \(current). Install it now? Halo restarts in a moment, and your rings and settings stay as they are."
        alert.accessoryView = Self.releaseNotesView(release.body)
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")
        switch run(alert) {
        case .alertFirstButtonReturn:
            Task { await installAvailableUpdate() }
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(version.description, forKey: Self.skippedKey)
            state = .upToDate
        default:
            break
        }
    }

    private func inform(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        run(alert)
    }

    @discardableResult
    private func run(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate()
        return alert.runModal()
    }

    /// Scrollable release notes for the update alert.
    private static func releaseNotesView(_ markdown: String?) -> NSView? {
        guard let markdown, !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let text = (try? AttributedString(markdown: markdown, options: options)).map(NSAttributedString.init)
            ?? NSAttributedString(string: markdown)
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 380, height: 160)
        scroll.borderType = .bezelBorder
        if let textView = scroll.documentView as? NSTextView {
            textView.isEditable = false
            textView.drawsBackground = false
            textView.textStorage?.setAttributedString(text)
            textView.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            textView.textColor = .labelColor
        }
        return scroll
    }

    // MARK: After an update

    /// On the first launch of a newer version, confirms the update and, when macOS has dropped
    /// the Accessibility grant (ad-hoc signed builds), helps turn it back on.
    private func handleFirstLaunchAfterUpdate() {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: Self.lastLaunchedKey).flatMap(SemanticVersion.init)
        defaults.set(currentVersion?.description, forKey: Self.lastLaunchedKey)
        guard let previous, let current = currentVersion, previous < current else { return }
        defaults.removeObject(forKey: Self.skippedKey)
        try? FileManager.default.removeItem(at: UpdateInstaller.stagingDirectory(for: current).deletingLastPathComponent())

        Task {
            try? await Task.sleep(for: .seconds(1.5))
            PermissionCenter.shared.refresh()
            guard PermissionCenter.shared.status(.accessibility) == .denied else {
                ToastPresenter.shared.show("Updated to Halo \(current)", symbol: "checkmark.circle", style: .success)
                return
            }
            let alert = NSAlert()
            alert.messageText = "Halo was updated to \(current)"
            alert.informativeText = "macOS turns Accessibility off for an app after it changes. Turn it back on so shortcuts, media keys and window actions keep working."
            alert.addButton(withTitle: "Turn On Accessibility")
            alert.addButton(withTitle: "Later")
            if run(alert) == .alertFirstButtonReturn { reenableAccessibility() }
        }
    }

    /// Asks again; PermissionCenter clears the stale entry left by the previous build first.
    private func reenableAccessibility() {
        PermissionCenter.shared.request(.accessibility)
    }
}
