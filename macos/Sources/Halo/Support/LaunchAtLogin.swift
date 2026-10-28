import Foundation
import ServiceManagement

/// Launch-at-login via `SMAppService.mainApp`.
///
/// The login item belongs to the app bundle, so it is only available when Halo runs from
/// `Halo.app`, not from a bare `swift build` executable.
enum LaunchAtLogin {
    enum Status: Equatable { case enabled, disabled, requiresApproval, unavailable(String) }

    /// A failed registration change, with a message that can be shown as is.
    struct Failure: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    static var status: Status {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return .unavailable("Open at Login works when Halo runs from its app, for example from the Applications folder.")
        }
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .notRegistered: return .disabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .unavailable("macOS couldn't find Halo's login item. Move Halo to the Applications folder and try again.")
        @unknown default: return .unavailable("macOS reported an unknown login item status.")
        }
    }

    /// Registers or unregisters the login item. Throws a user-readable error.
    ///
    /// Does nothing when the login item is already in the requested state (registered but
    /// awaiting the user's approval counts as on).
    static func setEnabled(_ enabled: Bool) throws {
        switch (enabled, status) {
        case (true, .enabled), (true, .requiresApproval), (false, .disabled), (false, .unavailable):
            return
        case (true, .unavailable(let reason)):
            throw Failure(message: reason)
        default:
            break
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            Log.app.info("Login item \(enabled ? "registered" : "unregistered", privacy: .public)")
        } catch {
            Log.app.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
            let action = enabled ? "add Halo to" : "remove Halo from"
            throw Failure(message: "macOS couldn't \(action) your login items: \(error.localizedDescription)")
        }
    }

    /// Opens System Settings › General › Login Items.
    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
