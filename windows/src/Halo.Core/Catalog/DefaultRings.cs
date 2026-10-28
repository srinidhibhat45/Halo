namespace Halo.Core.Catalog;

/// <summary>The rings a new user starts with, and the ready-made nested rings in the library.</summary>
public static class DefaultRings
{
    /// <summary>Notepad, launched by executable name; Windows 11 opens the Store Notepad from it.</summary>
    public static AppTarget Notepad { get; } = new("notepad.exe", "Notepad", @"%SystemRoot%\System32\notepad.exe");

    /// <summary>File Explorer.</summary>
    public static AppTarget FileExplorer { get; } = new("explorer.exe", "File Explorer", @"%SystemRoot%\explorer.exe");

    /// <summary>
    /// Eight everyday actions, clockwise from the top, mirroring the Mac app's default ring with
    /// Windows equivalents: snip, new note, play/pause, an AI folder, emoji, a window-layout folder,
    /// File Explorer and lock. Frequent actions sit on the axes.
    /// </summary>
    public static Ring Global() => new([
        new Slot(new ScreenshotAction(new ScreenshotOptions(ScreenshotMode.Area))),
        new Slot(new MacroAction(NewNote()), "New Note", new SymbolIcon("square.and.pencil")),
        new Slot(new MediaAction(MediaCommand.PlayPause)),
        new Slot(new FolderAction(Ai()), "AI", new SymbolIcon("sparkles")),
        new Slot(new SystemAction(SystemCommand.EmojiPicker)),
        new Slot(new FolderAction(Windows()), "Windows", new SymbolIcon("rectangle.split.2x1")),
        new Slot(new AppAction(FileExplorer)),
        new Slot(new SystemAction(SystemCommand.LockScreen)),
    ]);

    /// <summary>Opens (or switches to) Notepad and starts a new tab.</summary>
    public static Macro NewNote() => new([
        new MacroStep(new AppAction(Notepad), 0.6),
        new MacroStep(new KeystrokeAction(new KeyCombo(VirtualKeys.N, Modifiers.Control, "N")), 0),
    ]);

    public static Ring Ai() => new([
        new Slot(new AiPromptAction(new AiPrompt(AiService.Claude, "Summarize this in a few bullet points:\n\n{selection}")), "Summarize"),
        new Slot(new AiPromptAction(new AiPrompt(AiService.ChatGpt, "Reply to this message. Keep it short and friendly:\n\n{selection}")),
            "Reply with ChatGPT", new SymbolIcon("arrowshape.turn.up.left")),
        new Slot(new AiPromptAction(new AiPrompt(AiService.Claude, "Fix the grammar and spelling, keep my tone. Reply with the corrected text only:\n\n{selection}")),
            "Fix Writing", new SymbolIcon("checkmark.seal")),
        new Slot(new AiPromptAction(new AiPrompt(AiService.Perplexity, "{selection}")), "Search Perplexity", new SymbolIcon("magnifyingglass")),
        new Slot(new AiPromptAction(new AiPrompt(AiService.Claude, "Explain this simply:\n\n{selection}")), "Explain", new SymbolIcon("lightbulb")),
        new Slot(new AiPromptAction(new AiPrompt(AiService.Gemini, "{selection}")), "Ask Gemini", new SymbolIcon("sparkle")),
    ]);

    public static Ring Media() => new([
        new Slot(new MediaAction(MediaCommand.PlayPause)),
        new Slot(new MediaAction(MediaCommand.NextTrack)),
        new Slot(new MediaAction(MediaCommand.VolumeUp)),
        new Slot(new MediaAction(MediaCommand.Mute)),
        new Slot(new MediaAction(MediaCommand.VolumeDown)),
        new Slot(new MediaAction(MediaCommand.PreviousTrack)),
    ]);

    /// <summary>Maximize, snap right, next monitor, center, minimize, snap left (clockwise from the top).</summary>
    public static Ring Windows() => new([
        new Slot(new WindowAction(WindowCommand.Maximize)),
        new Slot(new WindowAction(WindowCommand.RightHalf)),
        new Slot(new WindowAction(WindowCommand.NextDisplay)),
        new Slot(new WindowAction(WindowCommand.Center)),
        new Slot(new WindowAction(WindowCommand.Minimize)),
        new Slot(new WindowAction(WindowCommand.LeftHalf)),
    ]);
}
