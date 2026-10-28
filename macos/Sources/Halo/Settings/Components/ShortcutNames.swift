import Observation

/// The names of the user's Apple Shortcuts, loaded once (from `ShortcutsLibrary`) and shared by
/// the Add to Ring picker, the library and the shortcut editor.
@Observable
final class ShortcutNames {
    static let shared = ShortcutNames()

    private(set) var names: [String] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false

    init() {}

    /// A list that is already known (snapshots and tests); never asks the `shortcuts` tool.
    init(preloaded names: [String]) {
        self.names = names
        self.hasLoaded = true
    }

    /// Loads the list the first time it is needed.
    func loadIfNeeded() {
        guard !hasLoaded, !isLoading else { return }
        reload()
    }

    /// Asks the Shortcuts app again (after the user added or renamed a shortcut).
    func reload() {
        guard !isLoading else { return }
        isLoading = true
        Task { @MainActor in
            names = await ShortcutsLibrary.names()
            isLoading = false
            hasLoaded = true
        }
    }
}
