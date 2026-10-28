import Foundation

/// The user's shortcuts from Apple's Shortcuts app (for the shortcut picker), via the `shortcuts`
/// command-line tool. The Shortcuts database itself is off limits (other teams' containers).
enum ShortcutsLibrary {
    /// Shortcut names, sorted; empty if none or the `shortcuts` tool is unavailable.
    static func names() async -> [String] {
        let result = await ProcessRunner.run("/usr/bin/shortcuts", ["list"], timeout: 10)
        guard result.succeeded else {
            let reason = result.launchError ?? (result.timedOut ? "timed out" : "exit \(result.status)")
            Log.actions.error("shortcuts list failed: \(reason, privacy: .public)")
            return []
        }
        // One exact name per line (kept untrimmed: it is what `shortcuts run` expects).
        let names = result.stdout
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return Array(Set(names)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
