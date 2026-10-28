import Foundation
import HaloCore

/// Smart Actions: steps in order, each followed by its delay, stopping at the first failure.
enum MacroRunner {
    /// Upper bound for one step's delay, so a typo can't stall the ring for hours.
    private static let maxDelay: Double = 60
    /// How long a step that acts on the frontmost app waits for the app the step before it opened.
    private static let frontmostTimeout: Duration = .seconds(2)

    static func run(_ macro: Macro, context: ActionContext) async -> ActionOutcome {
        guard !macro.steps.isEmpty else { return .failed("This Smart Action has no steps") }
        // Check up front so a macro never stops halfway for a permission the user can grant now.
        if Action.macro(macro).requiredPermissions.contains(.accessibility),
           let missing = PermissionCenter.shared.gate(.accessibility) {
            return missing
        }

        var last = ActionOutcome.success
        // The app the previous step brought to the front.
        var openedApp: AppTarget?
        for (index, step) in macro.steps.enumerated() {
            let label = "Step \(index + 1) (\(step.action.defaultTitle))"
            if Task.isCancelled { return .failed("Stopped before \(label.lowercased())") }
            if step.action.isFolder || step.action.kind == .macro {
                return .failed("\(label) can't run inside a Smart Action")
            }
            // Keys sent before the app just opened is in front would go to the app before it.
            if let app = openedApp, actsOnFrontmostApp(step.action),
               !(await AppActions.waitUntilFrontmost(bundleID: app.bundleID, timeout: frontmostTimeout)) {
                return .failed("\(label): \(app.name) didn't come to the front")
            }
            let bringsForward = appBroughtForward(by: step.action)
            var stepContext = context
            stepContext.slotTitle = step.action.defaultTitle
            let outcome = await ActionRunner.shared.perform(step.action, context: stepContext)
            switch outcome {
            case .needsPermission:
                return outcome
            case .failed(let reason):
                return .failed("\(label): \(reason)")
            case .success, .successWithMessage:
                last = outcome
            }
            openedApp = bringsForward
            let delay = min(max(step.delayAfter, 0), maxDelay)
            if index < macro.steps.count - 1, delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
        }
        // The last step's confirmation (e.g. "Copied to clipboard") describes the end result.
        return last
    }

    /// The app a step brings to the front: opening it, or toggling one that isn't frontmost
    /// (toggling the frontmost app hides it). Decided before the step runs.
    private static func appBroughtForward(by action: Action) -> AppTarget? {
        guard case .app(let target) = action else { return nil }
        switch target.behavior {
        case .open: return target
        case .toggle: return AppActions.isFrontmost(bundleID: target.bundleID) ? nil : target
        case .quit: return nil
        }
    }

    /// Steps that type into, read from or arrange the frontmost app.
    private static func actsOnFrontmostApp(_ action: Action) -> Bool {
        switch action {
        case .keystroke, .edit, .text, .window: true
        case .aiPrompt(let prompt): prompt.usesSelection
        case .shortcut(let shortcut): shortcut.passSelection
        case .system(let command): command == .emojiPicker || command == .dictation
        // In-app actions bring their own app forward.
        case .app, .url, .file, .media, .screenshot, .appleScript, .shell, .folder, .macro, .appShortcut, .menuItem, .clickButtons: false
        }
    }
}
