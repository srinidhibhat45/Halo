import AppKit
import HaloCore
import Observation

enum PermissionStatus: Equatable {
    case granted
    case denied
    /// Not asked yet / unknown (e.g. Automation before the first Apple Event).
    case notDetermined
}

/// Live status of the permissions Halo's actions need, with request and "open settings" helpers.
///
/// Accessibility and Screen Recording are checked synchronously (cheap TCC preflights). Automation
/// means "may send Apple Events to System Events" and is checked off the main thread, because
/// `AEDeterminePermissionToAutomateTarget` blocks.
@Observable
final class PermissionCenter {
    static let shared = PermissionCenter()

    private(set) var statuses: [Permission: PermissionStatus] = [:]

    @ObservationIgnored private var automationCheck: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var accessibilityObserver: NSObjectProtocol?

    nonisolated private static let systemEventsID = "com.apple.systemevents"
    private static let requestedKey = "PermissionCenter.requested"

    private init() {
        // Posted by the system whenever the Accessibility list changes (lets the UI update live).
        accessibilityObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                PermissionCenter.shared.refreshLocal()
            }
        }
        refreshLocal()
        // Don't launch System Events just because an action touched this; `refresh()` does.
        refreshAutomation(launchingSystemEvents: false)
    }

    func status(_ permission: Permission) -> PermissionStatus { statuses[permission] ?? .notDetermined }

    /// Re-checks all statuses (cheap; call when the settings window becomes key).
    func refresh() {
        refreshLocal()
        refreshAutomation(launchingSystemEvents: true)
    }

    /// Shows the system prompt where one exists, otherwise opens System Settings at the pane.
    func request(_ permission: Permission) {
        Log.permissions.info("Requesting \(permission.rawValue, privacy: .public)")
        switch permission {
        case .accessibility, .screenRecording:
            refreshLocal()
            guard status(permission) != .granted else { return }
            if hasRequested(permission) {
                // Asked before and still not granted. Often Halo *is* switched on in Settings, but
                // for an earlier build: macOS ties the grant to the build's code signature, so a
                // rebuilt or updated Halo is refused while the switch still shows on. Clear Halo's
                // own entry (only Halo's) so macOS lists this build afresh, then ask again.
                Self.resetEntry(for: permission)
                Log.permissions.notice("Cleared Halo's \(permission.rawValue, privacy: .public) entry and asked again")
            }
            markRequested(permission)
            if permission == .accessibility {
                // The literal key: `kAXTrustedCheckOptionPrompt` is a non-Sendable global in Swift 6.
                _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            } else {
                _ = CGRequestScreenCaptureAccess()
            }
            refreshLocal()
            openSystemSettings(for: permission)
        case .automation:
            Task {
                let result = await checkAutomation(prompting: true)
                if result == .denied { openSystemSettings(for: .automation) }
            }
        }
    }

    /// Opens System Settings › Privacy & Security at the right pane.
    func openSystemSettings(for permission: Permission) {
        let anchor = switch permission {
        case .accessibility: "Privacy_Accessibility"
        case .automation: "Privacy_Automation"
        case .screenRecording: "Privacy_ScreenCapture"
        }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
        pollUntilGranted(permission)
    }

    // MARK: Checks used by the action engine

    /// Live check: true when `permission` is granted. Automation uses the last known status (see
    /// `checkAutomation(prompting:launchingSystemEvents:)` for a fresh one).
    func isGranted(_ permission: Permission) -> Bool {
        switch permission {
        case .accessibility, .screenRecording:
            let status = Self.localStatus(permission, requested: hasRequested(permission))
            set(permission, status)
            return status == .granted
        case .automation:
            return status(.automation) == .granted
        }
    }

    /// nil when `permission` is granted, else the outcome an action should return.
    func gate(_ permission: Permission) -> ActionOutcome? {
        isGranted(permission) ? nil : .needsPermission(permission)
    }

    /// Fresh Automation status for System Events. The check needs System Events running; it is
    /// launched (hidden) unless `launchingSystemEvents` is false, in which case the last known
    /// status is kept. With `prompting` the system consent prompt appears when the user hasn't
    /// decided yet, and this waits for the answer.
    @discardableResult
    func checkAutomation(prompting: Bool, launchingSystemEvents: Bool = true) async -> PermissionStatus {
        if !Self.systemEventsIsRunning {
            guard launchingSystemEvents else { return status(.automation) }
            await Self.launchSystemEvents()
        }
        let timeout: TimeInterval = prompting ? 600 : 5
        // A System Events that was just launched takes a moment to accept Apple Events.
        for attempt in 0..<4 {
            if attempt > 0 { try? await Task.sleep(for: .milliseconds(250)) }
            guard let checked = await Background.run(timeout: timeout, { Self.automationStatus(prompting: prompting) }) else {
                break   // timed out (e.g. the consent prompt is still open)
            }
            if let status = checked {
                set(.automation, status)
                return status
            }
        }
        Log.permissions.notice("Automation status unavailable (System Events not reachable)")
        return status(.automation)
    }

    // MARK: Internals

    private func refreshLocal() {
        for permission in [Permission.accessibility, .screenRecording] {
            set(permission, Self.localStatus(permission, requested: hasRequested(permission)))
        }
    }

    private func refreshAutomation(launchingSystemEvents: Bool) {
        guard automationCheck == nil else { return }
        automationCheck = Task {
            await checkAutomation(prompting: false, launchingSystemEvents: launchingSystemEvents)
            automationCheck = nil
        }
    }

    private func set(_ permission: Permission, _ status: PermissionStatus) {
        guard statuses[permission] != status else { return }
        statuses[permission] = status
        Log.permissions.info("\(permission.rawValue, privacy: .public): \(String(describing: status), privacy: .public)")
    }

    /// Polls for a while after the user was sent to grant something, so the UI updates live.
    private func pollUntilGranted(_ permission: Permission) {
        pollTask?.cancel()
        pollTask = Task {
            for _ in 0..<120 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                if permission == .automation {
                    if await checkAutomation(prompting: false) == .granted { return }
                } else if isGranted(permission) {
                    return
                }
            }
        }
    }

    /// Removes Halo's entry for `permission` from macOS's privacy database (`tccutil reset`
    /// scoped to Halo's bundle identifier), so a stale grant for another build stops blocking it.
    private static func resetEntry(for permission: Permission) {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let service = switch permission {
        case .accessibility: "Accessibility"
        case .screenRecording: "ScreenCapture"
        case .automation: "AppleEvents"
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", service, bundleID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            Log.permissions.error("tccutil failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func hasRequested(_ permission: Permission) -> Bool {
        UserDefaults.standard.stringArray(forKey: Self.requestedKey)?.contains(permission.rawValue) ?? false
    }

    private func markRequested(_ permission: Permission) {
        var requested = Set(UserDefaults.standard.stringArray(forKey: Self.requestedKey) ?? [])
        requested.insert(permission.rawValue)
        UserDefaults.standard.set(requested.sorted(), forKey: Self.requestedKey)
    }

    /// Accessibility / Screen Recording have no "not asked" state in the API; "not granted and never
    /// requested" is reported as not determined.
    private static func localStatus(_ permission: Permission, requested: Bool) -> PermissionStatus {
        let granted = switch permission {
        case .accessibility: AXIsProcessTrusted() || CGPreflightPostEventAccess()
        case .screenRecording: CGPreflightScreenCaptureAccess()
        case .automation: false
        }
        if granted { return .granted }
        return requested ? .denied : .notDetermined
    }

    private static var systemEventsIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: systemEventsID).isEmpty
    }

    /// System Events is a faceless background app; launching it shows nothing.
    private static func launchSystemEvents() async {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: systemEventsID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } catch {
            Log.permissions.error("Could not launch System Events: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Blocking Apple Event consent check; nil when System Events isn't running (procNotFound).
    nonisolated private static func automationStatus(prompting: Bool) -> PermissionStatus? {
        guard let target = NSAppleEventDescriptor(bundleIdentifier: systemEventsID).aeDesc else { return nil }
        let status = AEDeterminePermissionToAutomateTarget(target, AEEventClass(typeWildCard), AEEventID(typeWildCard), prompting)
        switch Int(status) {
        case Int(noErr): return .granted
        case -1743: return .denied          // errAEEventNotPermitted
        case -1744: return .notDetermined   // errAEEventWouldRequireUserConsent
        case procNotFound: return nil
        default: return .notDetermined
        }
    }

    // MARK: Presentation

    /// User-facing name, why Halo needs it, and the SF Symbol used in the UI.
    static func title(_ permission: Permission) -> String {
        switch permission {
        case .accessibility: "Accessibility"
        case .automation: "Automation"
        case .screenRecording: "Screen Recording"
        }
    }

    static func reason(_ permission: Permission) -> String {
        switch permission {
        case .accessibility: "Send keyboard shortcuts, media keys and edit commands, move windows, and read selected text."
        case .automation: "Run AppleScripts and toggle Dark Mode through System Events."
        case .screenRecording: "Optional. Screenshot actions use the system's own shortcuts and don't need it; grant it only if a script you run captures the screen."
        }
    }

    static func symbol(_ permission: Permission) -> String {
        switch permission {
        case .accessibility: "accessibility"
        case .automation: "gearshape.2"
        case .screenRecording: "rectangle.dashed.badge.record"
        }
    }
}
