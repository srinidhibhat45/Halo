using System.Globalization;

namespace Halo.Core.Catalog;

/// <summary>A ready-made action shown in the configurator's library.</summary>
/// <param name="Id">Stable id, shared with the Mac app's catalog (e.g. <c>media.mute</c>).</param>
/// <param name="Symbol">SF Symbols name of its icon (drawn with <see cref="SymbolGlyphs"/>).</param>
/// <param name="Action">The action a slot gets when this template is assigned to it.</param>
/// <param name="NeedsSetup">A starting point that needs details (pick an app, record keys, write a
/// script…): the editor opens on assignment.</param>
/// <param name="Keywords">Extra words matched by search.</param>
public sealed record ActionTemplate(
    string Id,
    ActionCategory Category,
    string Title,
    string Subtitle,
    string Symbol,
    HaloAction Action,
    bool NeedsSetup = false,
    IReadOnlyList<string>? Keywords = null)
{
    public IReadOnlyList<string> SearchKeywords => Keywords ?? [];

    /// <summary>Whether the template's action can run on Windows.</summary>
    public ActionAvailability Availability => Action.Availability();
}

/// <summary>
/// Every built-in template, grouped by category. Installed apps are listed by the app itself
/// (Start-menu shortcuts); "Open App…" here is the generic entry point.
/// </summary>
public static class ActionCatalog
{
    private static readonly string[] SystemKeywords = ["windows", "pc"];

    public static IReadOnlyList<ActionTemplate> All { get; } =
    [
        .. Apps(), .. InApp(), .. Web(), .. Files(), .. MediaTemplates(), .. Screenshots(), .. SystemTemplates(),
        .. EditTemplates(), .. WindowTemplates(), .. Keyboard(), .. Shortcuts(), .. Scripts(), .. Text(),
        .. Ai(), .. Folders(), .. Macros(),
    ];

    public static IEnumerable<ActionTemplate> InCategory(ActionCategory category) => All.Where(t => t.Category == category);

    public static ActionTemplate? Template(string id) => All.FirstOrDefault(t => t.Id == id);

    /// <summary>Case- and accent-insensitive search over titles, subtitles, categories and keywords;
    /// every term must match.</summary>
    public static IReadOnlyList<ActionTemplate> Search(string query) =>
        All.Where(t => Matches(query, [t.Title, t.Subtitle, t.Category.Title(), .. t.SearchKeywords])).ToArray();

    /// <summary>True when every whitespace-separated term of <paramref name="query"/> occurs in one of
    /// <paramref name="fields"/> (ignoring case and accents). An empty query matches everything.</summary>
    public static bool Matches(string query, IEnumerable<string> fields)
    {
        var terms = query.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (terms.Length == 0) return true;
        var haystack = string.Join(' ', fields);
        var compare = CultureInfo.InvariantCulture.CompareInfo;
        return terms.All(term => compare.IndexOf(haystack, term, CompareOptions.IgnoreCase | CompareOptions.IgnoreNonSpace) >= 0);
    }

    private static IEnumerable<ActionTemplate> Apps() =>
    [
        new("app.choose", ActionCategory.Apps, "Open App…", "Launch or switch to an app", "app.badge",
            new AppAction(new AppTarget("", "App")), true, ["launch", "application", "open", "program"]),
        new("app.toggle", ActionCategory.Apps, "Toggle App…", "Show the app, or minimize it if it's in front", "app.connected.to.app.below.fill",
            new AppAction(new AppTarget("", "App", Behavior: AppBehavior.Toggle)), true, ["hide", "show", "minimize"]),
        new("app.quit", ActionCategory.Apps, "Close App…", "Close a running app", "xmark.app",
            new AppAction(new AppTarget("", "App", Behavior: AppBehavior.Quit)), true, ["quit", "exit", "close"]),
    ];

    private static IEnumerable<ActionTemplate> InApp() =>
    [
        new("inapp.shortcut", ActionCategory.InApp, "App Shortcut…", "A shortcut sent to one app, even from another app", "command.square",
            new AppShortcutAction(new AppShortcut("", "App", "", new KeyCombo(0x4D, Modifiers.Control | Modifiers.Shift, "M"))), true,
            ["in-app", "app action", "plugin", "teams", "zoom", "meeting"]),
        new("inapp.menu", ActionCategory.InApp, "Menu Command…", "A command from an app's menu bar (Mac only)", "filemenu.and.selection",
            new MenuItemAction(new MenuItemRef("", "App", [])), true, ["menu bar", "menu item", "command", "in-app", "mac"]),
    ];

    private static IEnumerable<ActionTemplate> Web() =>
    [
        new("url.custom", ActionCategory.Web, "Open Website…", "Any web page or app link", "globe",
            new UrlAction(new WebLink("https://")), true, ["url", "link", "browser", "site", "deep link"]),
    ];

    private static IEnumerable<ActionTemplate> Files() =>
    [
        new("file.choose", ActionCategory.Files, "Open File or Folder…", "Open anything with its default app", "doc",
            new FileAction(new FileTarget("")), true, ["document", "path"]),
        new("file.downloads", ActionCategory.Files, "Downloads", "Open your Downloads folder", "arrow.down.circle",
            new FileAction(new FileTarget("~/Downloads")), false, ["folder"]),
        new("file.desktop", ActionCategory.Files, "Desktop Folder", "Open your Desktop folder", "menubar.dock.rectangle",
            new FileAction(new FileTarget("~/Desktop")), false, ["folder"]),
        new("file.documents", ActionCategory.Files, "Documents", "Open your Documents folder", "doc.text",
            new FileAction(new FileTarget("~/Documents")), false, ["folder"]),
        new("file.home", ActionCategory.Files, "Home Folder", "Open your user folder", "house",
            new FileAction(new FileTarget("~")), false, ["folder", "user", "profile"]),
    ];

    private static IEnumerable<ActionTemplate> MediaTemplates() =>
        Enum.GetValues<MediaCommand>().Select(m => new ActionTemplate(
            $"media.{Serialization.EnumNames.Name(m)}", ActionCategory.Media, m.Title(), MediaSubtitle(m), m.Symbol(),
            new MediaAction(m), false, ["music", "audio", "sound", "media key"]));

    private static IEnumerable<ActionTemplate> Screenshots() =>
    [
        new("shot.area", ActionCategory.Screenshots, "Snip Area", "Drag to capture part of the screen", "rectangle.dashed",
            new ScreenshotAction(new ScreenshotOptions(ScreenshotMode.Area)), false, ["capture", "snip", "selection", "screenshot"]),
        new("shot.area.clip", ActionCategory.Screenshots, "Copy Area", "Capture an area to the clipboard", "rectangle.dashed.and.paperclip",
            new ScreenshotAction(new ScreenshotOptions(ScreenshotMode.Area, true)), false, ["capture", "clipboard", "snip"]),
        new("shot.window", ActionCategory.Screenshots, "Screenshot Window", "Capture the window in front", "macwindow",
            new ScreenshotAction(new ScreenshotOptions(ScreenshotMode.Window)), false, ["capture"]),
        new("shot.full", ActionCategory.Screenshots, "Screenshot Screen", "Capture the screen under the pointer", "display",
            new ScreenshotAction(new ScreenshotOptions(ScreenshotMode.FullScreen)), false, ["capture", "full screen", "print screen"]),
        new("shot.toolbar", ActionCategory.Screenshots, "Snipping Tool", "Open the Snipping Tool to capture or record", "camera.viewfinder",
            new ScreenshotAction(new ScreenshotOptions(ScreenshotMode.Toolbar)), false, ["record", "video", "capture"]),
    ];

    private static IEnumerable<ActionTemplate> SystemTemplates() =>
        Enum.GetValues<SystemCommand>().Select(s => new ActionTemplate(
            $"system.{Serialization.EnumNames.Name(s)}", ActionCategory.System, s.Title(), SystemSubtitle(s), s.Symbol(),
            new SystemAction(s), false, SystemKeywords));

    private static IEnumerable<ActionTemplate> EditTemplates() =>
        Enum.GetValues<EditCommand>().Select(e => new ActionTemplate(
            $"edit.{Serialization.EnumNames.Name(e)}", ActionCategory.Edit, e.Title(), $"Sends {e.KeyCombo().DisplayString} to the app in front", e.Symbol(),
            new EditAction(e), false, ["clipboard", "text"]));

    private static IEnumerable<ActionTemplate> WindowTemplates() =>
        Enum.GetValues<WindowCommand>().Select(w => new ActionTemplate(
            $"window.{Serialization.EnumNames.Name(w)}", ActionCategory.Window, w.Title(), WindowSubtitle(w), w.Symbol(),
            new WindowAction(w), false, ["window", "snap", "tile", "resize", "move"]));

    private static IEnumerable<ActionTemplate> Keyboard() =>
    [
        new("keys.custom", ActionCategory.Keyboard, "Keyboard Shortcut…", "Press any key combination in the app in front", "command",
            new KeystrokeAction(new KeyCombo(VirtualKeys.C, Modifiers.Control, "C")), true, ["hotkey", "keystroke", "keys"]),
    ];

    private static IEnumerable<ActionTemplate> Shortcuts() =>
    [
        new("shortcut.run", ActionCategory.Shortcuts, "Run Shortcut…", "Run a shortcut from Apple's Shortcuts app (Mac only)", "square.2.layers.3d.fill",
            new ShortcutAction(new ShortcutRef("")), true, ["automation", "workflow", "apple shortcuts", "mac"]),
    ];

    private static IEnumerable<ActionTemplate> Scripts() =>
    [
        new("script.applescript", ActionCategory.Scripts, "AppleScript…", "Run an AppleScript (Mac only)", "applescript.fill",
            new AppleScriptAction(new ScriptSource("display notification \"Hello from Halo\" with title \"Halo\"")), true, ["osascript", "automation", "mac"]),
        new("script.shell", ActionCategory.Scripts, "PowerShell Command…", "Run a PowerShell command in the background", "terminal.fill",
            new ShellAction(new ScriptSource("Start-Process \"$env:USERPROFILE\\Downloads\"")), true, ["powershell", "shell", "terminal", "command line", "script"]),
        new("script.cmd", ActionCategory.Scripts, "Command Prompt Command…", "Run a cmd.exe command in the background", "terminal",
            new ShellAction(new ScriptSource("start \"\" \"%USERPROFILE%\\Downloads\"", "cmd")), true, ["cmd", "batch", "shell", "command line"]),
    ];

    private static IEnumerable<ActionTemplate> Text() =>
    [
        new("text.custom", ActionCategory.Text, "Text Snippet…", "Paste saved text into the app in front", "text.cursor",
            new TextAction(new TextSnippet("")), true, ["snippet", "type", "paste", "signature", "template"]),
        new("text.date", ActionCategory.Text, "Today's Date", "Types the current date", "calendar",
            new TextAction(new TextSnippet("{date}")), false, ["snippet", "time"]),
    ];

    private static IEnumerable<ActionTemplate> Ai() =>
    [
        new("ai.summarize", ActionCategory.Ai, "Summarize", "Summarize the selected text", "text.append",
            new AiPromptAction(new AiPrompt(AiService.Claude, "Summarize this in a few bullet points:\n\n{selection}")), false, ["ai", "llm", "claude", "chatgpt"]),
        new("ai.proofread", ActionCategory.Ai, "Fix Writing", "Fix grammar and spelling in the selection", "checkmark.seal",
            new AiPromptAction(new AiPrompt(AiService.Claude, "Fix the grammar and spelling, keep my tone. Reply with the corrected text only:\n\n{selection}")), false, ["ai", "grammar", "proofread"]),
        new("ai.explain", ActionCategory.Ai, "Explain", "Explain the selected text simply", "lightbulb",
            new AiPromptAction(new AiPrompt(AiService.Claude, "Explain this simply:\n\n{selection}")), false, ["ai", "eli5"]),
        new("ai.translate", ActionCategory.Ai, "Translate", "Translate the selection to English", "character.bubble",
            new AiPromptAction(new AiPrompt(AiService.Claude, "Translate this to English:\n\n{selection}")), false, ["ai", "language"]),
        new("ai.custom", ActionCategory.Ai, "Custom Prompt…", "Your own prompt for ChatGPT, Claude and others", "sparkles",
            new AiPromptAction(new AiPrompt(AiService.Claude, "{selection}")), true, ["ai", "prompt builder"]),
    ];

    private static IEnumerable<ActionTemplate> Folders() =>
    [
        new("folder.empty", ActionCategory.Folders, "Nested Ring", "A slot that opens another ring", "circle.grid.cross.fill",
            new FolderAction(new Ring(6)), false, ["folder", "group", "submenu", "sub-ring"]),
        new("folder.media", ActionCategory.Folders, "Media Controls Ring", "Play, skip, volume and mute", "music.note",
            new FolderAction(DefaultRings.Media()), false, ["folder", "music"]),
        new("folder.windows", ActionCategory.Folders, "Window Layout Ring", "Snap, maximize, center and monitors", "rectangle.split.2x1",
            new FolderAction(DefaultRings.Windows()), false, ["folder", "snap", "tile"]),
    ];

    private static IEnumerable<ActionTemplate> Macros() =>
    [
        new("macro.custom", ActionCategory.Macros, "Smart Action…", "Chain several actions with delays", "wand.and.stars",
            new MacroAction(new Macro()), true, ["macro", "sequence", "multi-step", "workflow"]),
    ];

    private static string MediaSubtitle(MediaCommand m) => m switch
    {
        MediaCommand.PlayPause => "Play or pause what's playing",
        MediaCommand.NextTrack => "Skip to the next track",
        MediaCommand.PreviousTrack => "Go back a track",
        MediaCommand.VolumeUp => "Raise the volume",
        MediaCommand.VolumeDown => "Lower the volume",
        MediaCommand.Mute => "Mute or unmute sound",
        MediaCommand.BrightnessUp => "Brighten a laptop display",
        _ => "Dim a laptop display",
    };

    private static string SystemSubtitle(SystemCommand s) => s switch
    {
        SystemCommand.MissionControl => "See all open windows and desktops",
        SystemCommand.AppExpose => "Pick a window to switch to",
        SystemCommand.ShowDesktop => "Minimize everything to see the desktop",
        SystemCommand.Launchpad => "Open the Start menu",
        SystemCommand.NotificationCenter => "Open notifications and the calendar",
        SystemCommand.Spotlight => "Search your PC and the web",
        SystemCommand.Siri => "Open Copilot",
        SystemCommand.LockScreen => "Lock your PC",
        SystemCommand.SleepDisplay => "Turn the display off",
        SystemCommand.Sleep => "Put the PC to sleep",
        SystemCommand.ScreenSaver => "Start the screen saver",
        SystemCommand.EmojiPicker => "Insert emoji, GIFs and symbols",
        SystemCommand.Dictation => "Type with your voice",
        SystemCommand.ToggleDarkMode => "Switch between light and dark mode",
        SystemCommand.DoNotDisturb => "Not available on Windows",
        SystemCommand.ForceQuit => "See and end running apps",
        SystemCommand.SystemSettings => "Open Windows Settings",
        _ => "Open Wi-Fi, volume and other quick settings",
    };

    private static string WindowSubtitle(WindowCommand w) => w switch
    {
        WindowCommand.LeftHalf => "Move the window in front to the left half",
        WindowCommand.RightHalf => "Move the window in front to the right half",
        WindowCommand.TopHalf => "Move the window in front to the top half",
        WindowCommand.BottomHalf => "Move the window in front to the bottom half",
        WindowCommand.Maximize => "Maximize the window in front",
        WindowCommand.Center => "Center the window in front",
        WindowCommand.Minimize => "Minimize the window in front",
        WindowCommand.ToggleFullScreen => "Press F11 in the app in front",
        WindowCommand.NextDisplay => "Move the window to the next monitor",
        _ => "Close the window in front",
    };
}
