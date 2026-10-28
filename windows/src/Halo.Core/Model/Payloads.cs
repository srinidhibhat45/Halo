namespace Halo.Core;

public enum AppBehavior
{
    /// <summary>Launch, or bring to front if running.</summary>
    Open,
    /// <summary>Bring to front; if it already is in front, minimise it.</summary>
    Toggle,
    /// <summary>Close the app's windows (asks it to quit) if running.</summary>
    Quit,
}

/// <summary>An application to open, toggle or quit.</summary>
/// <param name="BundleId">
/// On Windows: the app's AppUserModelID (packaged and Store apps, e.g.
/// <c>Microsoft.WindowsNotepad_8wekyb3d8bbwe!App</c>) or its executable name (<c>chrome.exe</c>).
/// Also used to match the foreground app for app rings. JSON key: <c>bundleID</c>.
/// </param>
/// <param name="Path">Executable or <c>.lnk</c> path (environment variables allowed); used to launch and for the icon.</param>
public sealed record AppTarget(string BundleId, string Name, string? Path = null, AppBehavior Behavior = AppBehavior.Open);

/// <param name="Url">Any URL, including deep links (<c>ms-settings:</c>, <c>obsidian://</c>).</param>
/// <param name="OpenWithBundleId">Optional browser to open it with (executable name or path); null uses the default handler.</param>
public sealed record WebLink(string Url, string? OpenWithBundleId = null);

/// <param name="Path">Absolute path; <c>~</c> and <c>%VARIABLES%</c> are expanded at run time.</param>
/// <param name="Reveal">Select it in File Explorer instead of opening it. JSON key: <c>revealInFinder</c>.</param>
public sealed record FileTarget(string Path, bool Reveal = false)
{
    public string ExpandedPath => PathExpansion.Expand(Path);

    public string DisplayName => System.IO.Path.GetFileName(ExpandedPath.TrimEnd('/', '\\'));

    /// <summary>True for folders. Falls back to "no extension" when the path does not exist.</summary>
    public bool IsDirectory
    {
        get
        {
            var path = ExpandedPath;
            if (Directory.Exists(path)) return true;
            if (System.IO.File.Exists(path)) return false;
            return path.EndsWith('/') || path.EndsWith('\\') || !System.IO.Path.HasExtension(DisplayName);
        }
    }
}

/// <summary>Expands <c>~</c> (the user's profile folder) and <c>%VARIABLES%</c> in user-entered paths.</summary>
public static class PathExpansion
{
    public static string Expand(string path)
    {
        var expanded = path;
        if (expanded == "~" || expanded.StartsWith("~/", StringComparison.Ordinal) || expanded.StartsWith("~\\", StringComparison.Ordinal))
        {
            var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            var rest = expanded.Length > 2 ? expanded[2..] : "";
            expanded = rest.Length == 0 ? home : System.IO.Path.Combine(home, rest);
        }
        expanded = Environment.ExpandEnvironmentVariables(expanded);
        return System.IO.Path.DirectorySeparatorChar == '\\' ? expanded.Replace('/', '\\') : expanded;
    }
}

public enum MediaCommand
{
    PlayPause, NextTrack, PreviousTrack,
    VolumeUp, VolumeDown, Mute,
    BrightnessUp, BrightnessDown,
}

public enum ScreenshotMode
{
    /// <summary>Drag to select an area (Snipping Tool's area snip).</summary>
    Area,
    /// <summary>The window that was in front.</summary>
    Window,
    /// <summary>The whole screen under the pointer.</summary>
    FullScreen,
    /// <summary>The Snipping Tool app.</summary>
    Toolbar,
}

/// <param name="ToClipboard">Copy to the clipboard instead of saving a file (ignored for <see cref="ScreenshotMode.Toolbar"/>).</param>
public sealed record ScreenshotOptions(ScreenshotMode Mode, bool ToClipboard = false);

/// <summary>
/// System commands. The names are the macOS app's (so configs are shared); on Windows they map to
/// the nearest equivalent (Mission Control → Task View, Spotlight → Search, Force Quit → Task
/// Manager…). <see cref="QuickSettings"/> is Windows-only; the Mac app reads it as an empty slot.
/// </summary>
public enum SystemCommand
{
    MissionControl, AppExpose, ShowDesktop, Launchpad,
    NotificationCenter, Spotlight, Siri,
    LockScreen, SleepDisplay, Sleep, ScreenSaver,
    EmojiPicker, Dictation,
    ToggleDarkMode, DoNotDisturb,
    ForceQuit, SystemSettings,
    QuickSettings,
}

public enum EditCommand
{
    Copy, Cut, Paste, PasteAndMatchStyle, Undo, Redo, SelectAll, Find,
}

public enum WindowCommand
{
    LeftHalf, RightHalf, TopHalf, BottomHalf,
    Maximize, Center, Minimize, ToggleFullScreen, NextDisplay, Close,
}

/// <summary>A shortcut in Apple's Shortcuts app (macOS only).</summary>
public sealed record ShortcutRef(string Name, bool PassSelection = false);

/// <summary>How an in-app action reaches its app.</summary>
public enum AppDelivery
{
    /// <summary>Send to the app; if another app is in front, bring this one forward first.</summary>
    BringToFront,
    /// <summary>Bring the app forward, send, then return to the app you were in (e.g. mute a call
    /// without leaving your document).</summary>
    BringToFrontAndReturn,
}

/// <summary>A keyboard shortcut that belongs to a specific app.</summary>
/// <param name="BundleId">The app's executable name or AppUserModelID (JSON key <c>bundleID</c>).</param>
/// <param name="Title">What it does, e.g. "Mute / Unmute".</param>
/// <param name="Symbol">SF Symbols name of the icon shown on the ring, or null for the default.</param>
public sealed record AppShortcut(string BundleId, string AppName, string Title, KeyCombo Combo, string? Symbol = null,
    AppDelivery Delivery = AppDelivery.BringToFront);

/// <summary>A command in an app's menu bar by titles from the top menu down, e.g. ["View", "Show Sidebar"] (macOS only).</summary>
public sealed record MenuItemRef(string BundleId, string AppName, IReadOnlyList<string> Path, AppDelivery Delivery = AppDelivery.BringToFront)
{
    public bool Equals(MenuItemRef? other) =>
        other is not null && BundleId == other.BundleId && AppName == other.AppName && Delivery == other.Delivery && Path.SequenceEqual(other.Path);

    public override int GetHashCode() => HashCode.Combine(BundleId, AppName, Path.Count, Delivery);
}

/// <param name="Shell">
/// For shell scripts: null or <c>powershell</c> runs Windows PowerShell, <c>pwsh</c> PowerShell 7,
/// <c>cmd</c> the Command Prompt; any other value names an executable that reads the script on stdin.
/// </param>
public sealed record ScriptSource(string Source, string? Shell = null);

public enum TextMethod
{
    /// <summary>Put on the clipboard, press Ctrl+V, then restore the previous clipboard. Fast and exact.</summary>
    Paste,
    /// <summary>Type it character by character. Works where paste is blocked.</summary>
    Type,
}

/// <param name="Text">Supports placeholders: <c>{date}</c>, <c>{time}</c>, <c>{clipboard}</c>, <c>{selection}</c>.</param>
public sealed record TextSnippet(string Text, TextMethod Method = TextMethod.Paste, bool PressReturn = false);

public enum AiService
{
    ChatGpt, Claude, Perplexity, Gemini, Custom,
}

/// <param name="Template">Prompt text; <c>{selection}</c> is replaced by the text selected in the front app.</param>
/// <param name="CustomUrlTemplate">For <see cref="AiService.Custom"/>: a URL containing <c>{prompt}</c>. JSON key: <c>customURLTemplate</c>.</param>
public sealed record AiPrompt(AiService Service, string Template, string? CustomUrlTemplate = null)
{
    public bool UsesSelection => Template.Contains("{selection}", StringComparison.Ordinal);
}

public static class AiServiceInfo
{
    public static string DisplayName(this AiService service) => service switch
    {
        AiService.ChatGpt => "ChatGPT",
        AiService.Claude => "Claude",
        AiService.Perplexity => "Perplexity",
        AiService.Gemini => "Gemini",
        _ => "Custom URL",
    };

    /// <summary>
    /// URL template with a <c>{prompt}</c> placeholder (percent-encoded at run time), or null when the
    /// service has no prefill URL; the prompt is then copied to the clipboard and the site opened.
    /// </summary>
    public static string? UrlTemplate(this AiService service) => service switch
    {
        AiService.ChatGpt => "https://chatgpt.com/?q={prompt}",
        AiService.Claude => "https://claude.ai/new?q={prompt}",
        AiService.Perplexity => "https://www.perplexity.ai/search?q={prompt}",
        _ => null,
    };

    public static string HomeUrl(this AiService service) => service switch
    {
        AiService.ChatGpt => "https://chatgpt.com/",
        AiService.Claude => "https://claude.ai/new",
        AiService.Perplexity => "https://www.perplexity.ai/",
        AiService.Gemini => "https://gemini.google.com/app",
        _ => "",
    };
}

/// <summary>A sequence of actions run in order.</summary>
public sealed record Macro(IReadOnlyList<MacroStep> Steps)
{
    public Macro() : this(Array.Empty<MacroStep>()) { }

    public bool Equals(Macro? other) => other is not null && Steps.SequenceEqual(other.Steps);

    public override int GetHashCode() => Steps.Count;
}

/// <param name="Action">Any action except folders and macros.</param>
/// <param name="DelayAfter">Pause after this step, in seconds.</param>
public sealed record MacroStep(Guid Id, HaloAction Action, double DelayAfter = 0.15)
{
    public MacroStep(HaloAction action, double delayAfter = 0.15) : this(Guid.NewGuid(), action, delayAfter) { }
}
