import AppKit
import HaloCore

/// Where an action runs.
struct ActionContext {
    /// The app that was frontmost when the ring opened (receives keystrokes, window commands).
    var frontmostApp: NSRunningApplication?
    /// Title of the slot, for feedback messages.
    var slotTitle: String
    /// Where the ring was centred (screen coordinates, AppKit y-up), e.g. for the screen to capture.
    var ringCenter: CGPoint?
}

enum ActionOutcome: Equatable {
    case success
    /// Ran, with a short confirmation worth showing (e.g. "Copied to clipboard").
    case successWithMessage(String)
    /// Could not run because a permission is missing.
    case needsPermission(Permission)
    /// Failed with a user-readable reason.
    case failed(String)
}

/// Runs actions. Call after the ring has been dismissed so keystrokes reach the frontmost app.
///
/// Every action checks the permission it needs first and returns `.needsPermission` rather than
/// failing silently (macOS drops synthetic events from untrusted apps without an error).
/// Keystroke-based actions wait for the trigger's modifiers to be released before posting.
/// Blocking work (Accessibility IPC, child processes, Apple Event checks) runs off the main actor.
final class ActionRunner {
    static let shared = ActionRunner()

    private init() {}

    func run(_ action: Action, context: ActionContext) async -> ActionOutcome {
        let outcome = await perform(action, context: context)
        let kind = action.kind.rawValue
        switch outcome {
        case .success, .successWithMessage:
            Log.actions.info("Ran \(kind, privacy: .public)")
        case .needsPermission(let permission):
            Log.actions.notice("\(kind, privacy: .public) needs \(permission.rawValue, privacy: .public)")
        case .failed(let reason):
            Log.actions.error("\(kind, privacy: .public) failed: \(reason)")
        }
        return outcome
    }

    /// Runs one action without logging (macros call this for each step).
    func perform(_ action: Action, context: ActionContext) async -> ActionOutcome {
        switch action {
        case .app(let target): await AppActions.run(target)
        case .url(let link): await AppActions.open(link)
        case .file(let file): await AppActions.open(file)
        case .keystroke(let combo): await KeyActions.run(combo)
        case .media(let command): await MediaActions.run(command, context: context)
        case .screenshot(let options): await ScreenshotActions.run(options)
        case .system(let command): await SystemActions.run(command)
        case .edit(let command): await KeyActions.run(command)
        case .window(let command): await WindowActions.run(command, context: context)
        case .shortcut(let shortcut): await ScriptActions.runShortcut(shortcut)
        case .appShortcut(let shortcut): await InAppActions.run(shortcut, context: context)
        case .menuItem(let item): await InAppActions.run(item, context: context)
        case .appleScript(let script): await ScriptActions.runAppleScript(script)
        case .shell(let script): await ScriptActions.runShell(script)
        case .text(let snippet): await TextActions.run(snippet)
        case .aiPrompt(let prompt): await AIPromptActions.run(prompt)
        // The overlay opens nested rings itself; there is nothing to run.
        case .folder: .success
        case .macro(let macro): await MacroRunner.run(macro, context: context)
        }
    }
}
