import AppKit
import HaloCore

/// Presents the outcome of a ring action as a toast where the ring was: missing permissions
/// (with "Open Settings"), failures, messages, and a brief confirmation after actions whose
/// effect isn't visible on screen. With "Show confirmations" off, actions without a visible
/// effect stay silent unless something went wrong.
enum ActionFeedback {
    /// How long the plain confirmation stays: long enough to register, short enough to ignore.
    private static let confirmationDuration: TimeInterval = 0.8

    static func present(_ outcome: ActionOutcome, slot: Slot, action: Action, anchor: CGPoint?) {
        let toasts = ToastPresenter.shared
        switch outcome {
        case .success:
            guard AppModel.shared.settings.showConfirmations, hasNoVisibleEffect(action) else { return }
            toasts.show(slot.displayTitle, symbol: symbol(for: slot, action: action), style: .info,
                        duration: confirmationDuration, anchor: anchor)
        case .successWithMessage(let message):
            // After an action with no visible effect, a message ("Copied", a script's output) is
            // a confirmation too.
            guard AppModel.shared.settings.showConfirmations || !hasNoVisibleEffect(action) else { return }
            toasts.show(message, symbol: symbol(for: slot, action: action), style: .success, anchor: anchor)
        case .needsPermission(let permission):
            Feedback.play(.reject)
            let button = ToastPresenter.Button(title: "Open Settings") {
                PermissionCenter.shared.openSystemSettings(for: permission)
            }
            toasts.show("\(slot.displayTitle) needs \(PermissionCenter.title(permission)) access.",
                        symbol: PermissionCenter.symbol(permission), style: .warning, button: button,
                        duration: 6, anchor: anchor)
        case .failed(let reason):
            Feedback.play(.reject)
            toasts.show(reason, symbol: "exclamationmark.triangle.fill", style: .error, duration: 4, anchor: anchor)
        }
    }

    /// True for actions that leave nothing on screen to show they worked. Volume, brightness and
    /// mute are left out: macOS shows its own HUD for them.
    static func hasNoVisibleEffect(_ action: Action) -> Bool {
        switch action {
        case .edit(let command): command == .copy || command == .cut
        case .media(let command): command == .playPause || command == .nextTrack || command == .previousTrack
        case .system(let command): command == .toggleDarkMode || command == .doNotDisturb
        case .keystroke, .text, .shortcut, .appleScript, .shell, .macro, .appShortcut, .menuItem: true
        case .app, .url, .file, .screenshot, .window, .aiPrompt, .folder: false
        }
    }

    /// The slot's SF Symbol; slots drawn with an app icon, image or emoji use the action's symbol.
    private static func symbol(for slot: Slot, action: Action) -> String {
        if case .symbol(let name)? = slot.displayIcon { return name }
        return action.defaultSymbol
    }
}
