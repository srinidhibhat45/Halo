import AppKit
import HaloCore

/// AppleScript, shell scripts and Apple Shortcuts, each in its own killable child process.
///
/// Children run under Halo's privacy identity: an AppleScript that controls another app triggers
/// an Automation prompt naming Halo, and a script that touches protected folders asks in Halo's name.
enum ScriptActions {
    private static let shellTimeout: TimeInterval = 30
    /// AppleScripts and shortcuts may wait on a dialog the user has to answer.
    private static let interactiveTimeout: TimeInterval = 120

    // MARK: AppleScript

    static func runAppleScript(_ script: ScriptSource) async -> ActionOutcome {
        guard !script.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failed("The script is empty")
        }
        let result = await ProcessRunner.run("/usr/bin/osascript", ["-e", script.source], timeout: interactiveTimeout)
        if let launchError = result.launchError { return .failed("Couldn't start osascript: \(launchError)") }
        if result.timedOut { return .failed("The script ran too long and was stopped") }
        if result.status == 0 { return outputOutcome(result.stdout) }
        let error = result.stderr
        if error.contains("(-1743)") { return .needsPermission(.automation) }   // errAEEventNotPermitted
        if error.contains("(-128)") { return .success }                         // user cancelled a dialog
        return .failed(appleScriptMessage(error))
    }

    /// "0:12: execution error: Finder got an error: … (-1728)" → "Finder got an error: …".
    private static func appleScriptMessage(_ stderr: String) -> String {
        guard var line = ProcessResult.firstLine(of: stderr, limit: 400) else { return "The script failed" }
        if let range = line.range(of: #"^\d+:\d+: "#, options: .regularExpression) { line.removeSubrange(range) }
        for prefix in ["execution error: ", "syntax error: "] where line.hasPrefix(prefix) {
            line = (prefix == "syntax error: " ? "Syntax error: " : "") + line.dropFirst(prefix.count)
        }
        if let range = line.range(of: #"\s*\(-?\d+\)$"#, options: .regularExpression) { line.removeSubrange(range) }
        return ProcessResult.firstLine(of: line) ?? "The script failed"
    }

    // MARK: Shell

    static func runShell(_ script: ScriptSource) async -> ActionOutcome {
        guard !script.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failed("The script is empty")
        }
        let shell = script.shell.flatMap { $0.isEmpty ? nil : ($0 as NSString).expandingTildeInPath } ?? loginShell()
        guard FileManager.default.isExecutableFile(atPath: shell) else { return .failed("Shell not found: \(shell)") }
        // A login shell reads ~/.zprofile etc., so Homebrew and other PATH additions apply.
        let isLoginCapable = ["sh", "bash", "zsh", "dash", "ksh", "fish", "tcsh", "csh"]
            .contains((shell as NSString).lastPathComponent)
        let arguments = (isLoginCapable ? ["-l"] : []) + ["-c", script.source]
        let result = await ProcessRunner.run(shell, arguments, timeout: shellTimeout,
                                             workingDirectory: FileManager.default.homeDirectoryForCurrentUser)
        if let launchError = result.launchError { return .failed("Couldn't start the shell: \(launchError)") }
        if result.timedOut { return .failed("The script ran longer than \(Int(shellTimeout)) s and was stopped") }
        if result.status == 0 { return outputOutcome(result.stdout) }
        let detail = ProcessResult.firstLine(of: result.stderr) ?? ProcessResult.firstLine(of: result.stdout)
        return .failed("Script failed (exit \(result.status))" + (detail.map { ": \($0)" } ?? ""))
    }

    private static func loginShell() -> String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if !path.isEmpty { return path }
        }
        return "/bin/zsh"
    }

    /// A script's first line of output makes a useful confirmation ("Done", a result value).
    private static func outputOutcome(_ stdout: String) -> ActionOutcome {
        ProcessResult.firstLine(of: stdout).map(ActionOutcome.successWithMessage) ?? .success
    }

    // MARK: Apple Shortcuts

    static func runShortcut(_ shortcut: ShortcutRef) async -> ActionOutcome {
        let name = shortcut.name
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .failed("Choose a shortcut to run") }
        var arguments = ["run"]
        var inputFile: URL?
        if shortcut.passSelection {
            if let missing = PermissionCenter.shared.gate(.accessibility) { return missing }
            if let selection = await SelectionReader.read(), !selection.isEmpty {
                // The CLI takes input as files; the shortcut receives this as text.
                let file = FileManager.default.temporaryDirectory.appendingPathComponent("Halo-\(UUID().uuidString).txt")
                do {
                    try Data(selection.utf8).write(to: file, options: .atomic)
                    inputFile = file
                    arguments += ["--input-path", file.path]
                } catch {
                    return .failed("Couldn't pass the selection to the shortcut")
                }
            }
        }
        defer { if let inputFile { try? FileManager.default.removeItem(at: inputFile) } }
        // "--" so a name starting with "-" isn't read as an option.
        arguments += ["--", name]

        let result = await ProcessRunner.run("/usr/bin/shortcuts", arguments, timeout: interactiveTimeout)
        if result.launchError != nil { return .failed("Shortcuts isn't available") }
        if result.timedOut { return .failed("“\(name)” ran too long and was stopped") }
        if result.status == 0 { return .success }
        let detail = ProcessResult.firstLine(of: result.stderr).map { line in
            line.hasPrefix("Error: ") ? String(line.dropFirst("Error: ".count)) : line
        }
        let lowered = detail?.lowercased() ?? ""
        if lowered.contains("couldn’t find") || lowered.contains("couldn't find") || lowered.contains("not found") {
            return .failed("No shortcut named “\(name)”")
        }
        return .failed("“\(name)” failed" + (detail.map { ": \($0)" } ?? ""))
    }
}
