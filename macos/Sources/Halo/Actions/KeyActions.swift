import AppKit
import HaloCore

/// Recorded keyboard shortcuts and the standard edit commands, sent to the frontmost app.
enum KeyActions {
    static func run(_ combo: KeyCombo) async -> ActionOutcome {
        if let missing = PermissionCenter.shared.gate(.accessibility) { return missing }
        await KeySender.waitForTriggerRelease()
        let sent: Bool
        if let character = shownCharacter(of: combo) {
            sent = await KeySender.press(character: character, modifiers: combo.modifiers.cgEventFlags,
                                         fallback: CGKeyCode(combo.keyCode))
        } else {
            sent = await KeySender.press(combo)
        }
        return sent ? .success : .failed("Couldn't send \(combo.displayString)")
    }

    /// The character to press for `combo` when its key no longer types what its label shows.
    /// Built-in shortcuts (New Note's ⌘N) are stored by ANSI key position, so on Dvorak or AZERTY
    /// they go by the letter they show, like the edit commands; so does a combo recorded in
    /// another layout. nil: press the recorded key.
    private static func shownCharacter(of combo: KeyCombo) -> Character? {
        guard combo.keyLabel.count == 1, KeyboardLayout.label(forKeyCode: combo.keyCode) != combo.keyLabel else { return nil }
        return combo.keyLabel.lowercased().first
    }

    /// Edit commands go by character (resolved in the current layout), not by key position, so ⌘C
    /// still copies on Dvorak, AZERTY and friends.
    static func run(_ command: EditCommand) async -> ActionOutcome {
        if let missing = PermissionCenter.shared.gate(.accessibility) { return missing }
        await KeySender.waitForTriggerRelease()
        switch command {
        case .copy, .cut, .paste, .pasteAndMatchStyle:
            // Not while another action has its own text on the pasteboard.
            return await ClipboardLock.run { await press(command) }
        case .undo, .redo, .selectAll, .find:
            return await press(command)
        }
    }

    private static func press(_ command: EditCommand) async -> ActionOutcome {
        let combo = command.keyCombo
        let character = combo.keyLabel.lowercased().first ?? "c"
        let before = Clipboard.changeCount
        guard await KeySender.press(character: character, modifiers: combo.modifiers.cgEventFlags,
                                    fallback: CGKeyCode(combo.keyCode)) else {
            return .failed("Couldn't send \(combo.displayString)")
        }
        switch command {
        case .copy, .cut:
            // Confirm only when the app actually put something on the pasteboard.
            guard await Clipboard.waitForChange(from: before, timeout: .milliseconds(500)) else { return .success }
            return .successWithMessage(command == .copy ? "Copied to clipboard" : "Cut to clipboard")
        case .paste, .pasteAndMatchStyle, .undo, .redo, .selectAll, .find:
            return .success
        }
    }
}
