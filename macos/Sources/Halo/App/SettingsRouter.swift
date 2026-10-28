import AppKit
import HaloCore
import Observation

/// Where the configurator should open.
enum SettingsDestination: Hashable {
    /// A ring editor; `path` opens a nested ring, `slot` pre-selects a slot.
    case ring(RingTarget, path: [Int] = [], slot: Int? = nil)
    case general
    case appearance
    case permissions
    case about
}

/// Opens the configurator at a destination from anywhere (menu bar, overlay, onboarding).
///
/// The settings window observes `destination` and `requestCount`. Windows are AppKit-managed
/// (`WindowCoordinator`) so they open reliably from non-view code in an LSUIElement app.
@Observable
final class SettingsRouter {
    static let shared = SettingsRouter()

    /// The pane to show.
    var destination: SettingsDestination = .ring(.global)
    /// Bumped on every request so the window reacts even to the same destination twice.
    var requestCount = 0
    /// Whether the latest request named a destination (a plain `open()` keeps the user's pane).
    private(set) var lastRequestNamedDestination = false

    func open(_ destination: SettingsDestination? = nil) {
        lastRequestNamedDestination = destination != nil
        if let destination { self.destination = destination }
        requestCount += 1
        WindowCoordinator.shared.show(.settings)
    }

    func openOnboarding() {
        WindowCoordinator.shared.show(.onboarding)
    }
}
