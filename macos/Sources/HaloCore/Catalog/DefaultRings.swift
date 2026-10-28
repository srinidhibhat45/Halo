import Foundation

/// The rings a new user starts with, and the ready-made nested rings in the library.
public enum DefaultRings {
    /// Eight everyday actions, clockwise from the top, modelled on Logitech's default Mac ring
    /// (play/pause, new note, lock, screenshot, emoji, Finder, an AI folder) with Halo's own
    /// window ring in place of Logitech's settings shortcut. Frequent actions sit on the axes.
    public static func global() -> Ring {
        Ring(slots: [
            Slot(action: .screenshot(ScreenshotOptions(mode: .area))),
            Slot(action: .macro(newNote()), title: "New Note", icon: .symbol(name: "square.and.pencil")),
            Slot(action: .media(.playPause)),
            Slot(action: .folder(ai()), title: "AI", icon: .symbol(name: "sparkles")),
            Slot(action: .system(.emojiPicker)),
            Slot(action: .folder(windows()), title: "Windows", icon: .symbol(name: "rectangle.split.2x1")),
            Slot(action: .app(AppTarget(bundleID: "com.apple.finder", name: "Finder", path: "/System/Library/CoreServices/Finder.app"))),
            Slot(action: .system(.lockScreen)),
        ])
    }

    /// Opens Notes and starts a new note.
    public static func newNote() -> Macro {
        Macro(steps: [
            MacroStep(action: .app(AppTarget(bundleID: "com.apple.Notes", name: "Notes", path: "/System/Applications/Notes.app")), delayAfter: 0.6),
            MacroStep(action: .keystroke(KeyCombo(keyCode: KeyCode.n, modifiers: .command, keyLabel: "N")), delayAfter: 0),
        ])
    }

    public static func ai() -> Ring {
        Ring(slots: [
            Slot(action: .aiPrompt(AIPrompt(service: .claude, template: "Summarize this in a few bullet points:\n\n{selection}")), title: "Summarize"),
            Slot(action: .aiPrompt(AIPrompt(service: .chatGPT, template: "Reply to this message. Keep it short and friendly:\n\n{selection}")), title: "Reply with ChatGPT", icon: .symbol(name: "arrowshape.turn.up.left")),
            Slot(action: .aiPrompt(AIPrompt(service: .claude, template: "Fix the grammar and spelling, keep my tone. Reply with the corrected text only:\n\n{selection}")), title: "Fix Writing", icon: .symbol(name: "checkmark.seal")),
            Slot(action: .aiPrompt(AIPrompt(service: .perplexity, template: "{selection}")), title: "Search Perplexity", icon: .symbol(name: "magnifyingglass")),
            Slot(action: .aiPrompt(AIPrompt(service: .claude, template: "Explain this simply:\n\n{selection}")), title: "Explain", icon: .symbol(name: "lightbulb")),
            Slot(action: .aiPrompt(AIPrompt(service: .gemini, template: "{selection}")), title: "Ask Gemini", icon: .symbol(name: "sparkle")),
        ])
    }

    public static func media() -> Ring {
        Ring(slots: [
            Slot(action: .media(.playPause)),
            Slot(action: .media(.nextTrack)),
            Slot(action: .media(.volumeUp)),
            Slot(action: .media(.mute)),
            Slot(action: .media(.volumeDown)),
            Slot(action: .media(.previousTrack)),
        ])
    }

    public static func windows() -> Ring {
        Ring(slots: [
            Slot(action: .window(.maximize)),
            Slot(action: .window(.rightHalf)),
            Slot(action: .window(.nextDisplay)),
            Slot(action: .window(.center)),
            Slot(action: .window(.minimize)),
            Slot(action: .window(.leftHalf)),
        ])
    }
}
