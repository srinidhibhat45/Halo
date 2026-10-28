namespace Halo.Core.Catalog;

/// <summary>Groups shown in the action library.</summary>
public enum ActionCategory
{
    Apps, InApp, Web, Files, Media, Screenshots, System, Edit, Window, Keyboard,
    Shortcuts, Scripts, Text, Ai, Folders, Macros,
}

/// <summary>Whether an action can run on Windows, and why not.</summary>
public sealed record ActionAvailability(bool IsAvailable, string? Reason)
{
    public static ActionAvailability Available { get; } = new(true, null);

    public static ActionAvailability Unavailable(string reason) => new(false, reason);
}

/// <summary>Titles, symbols, categories and availability of actions as Windows shows them.</summary>
/// <remarks>
/// Symbols are SF Symbols names, shared with the Mac app so configs stay portable; the Windows
/// renderer draws them with <see cref="SymbolGlyphs"/>.
/// </remarks>
public static class ActionPresentation
{
    public static string Title(this ActionCategory category) => category switch
    {
        ActionCategory.Apps => "Apps",
        ActionCategory.InApp => "In-App Actions",
        ActionCategory.Web => "Websites & Links",
        ActionCategory.Files => "Files & Folders",
        ActionCategory.Media => "Media",
        ActionCategory.Screenshots => "Screenshots",
        ActionCategory.System => "System",
        ActionCategory.Edit => "Edit",
        ActionCategory.Window => "Windows",
        ActionCategory.Keyboard => "Keyboard Shortcut",
        ActionCategory.Shortcuts => "Apple Shortcuts",
        ActionCategory.Scripts => "Scripts",
        ActionCategory.Text => "Text Snippets",
        ActionCategory.Ai => "AI Prompts",
        ActionCategory.Folders => "Nested Rings",
        _ => "Smart Actions",
    };

    public static string Symbol(this ActionCategory category) => category switch
    {
        ActionCategory.Apps => "square.grid.2x2",
        ActionCategory.InApp => "app.badge.checkmark",
        ActionCategory.Web => "globe",
        ActionCategory.Files => "folder",
        ActionCategory.Media => "playpause",
        ActionCategory.Screenshots => "camera.viewfinder",
        ActionCategory.System => "gearshape",
        ActionCategory.Edit => "doc.on.clipboard",
        ActionCategory.Window => "macwindow",
        ActionCategory.Keyboard => "command",
        ActionCategory.Shortcuts => "square.2.layers.3d",
        ActionCategory.Scripts => "terminal",
        ActionCategory.Text => "text.cursor",
        ActionCategory.Ai => "sparkles",
        ActionCategory.Folders => "circle.grid.cross",
        _ => "wand.and.stars",
    };

    public static ActionCategory Category(this HaloAction action) => action switch
    {
        AppAction => ActionCategory.Apps,
        UrlAction => ActionCategory.Web,
        FileAction => ActionCategory.Files,
        KeystrokeAction => ActionCategory.Keyboard,
        MediaAction => ActionCategory.Media,
        ScreenshotAction => ActionCategory.Screenshots,
        SystemAction => ActionCategory.System,
        EditAction => ActionCategory.Edit,
        WindowAction => ActionCategory.Window,
        ShortcutAction => ActionCategory.Shortcuts,
        AppShortcutAction or MenuItemAction => ActionCategory.InApp,
        AppleScriptAction or ShellAction => ActionCategory.Scripts,
        TextAction => ActionCategory.Text,
        AiPromptAction => ActionCategory.Ai,
        FolderAction => ActionCategory.Folders,
        _ => ActionCategory.Macros,
    };

    /// <summary>Default label when the slot has no custom title.</summary>
    public static string DefaultTitle(this HaloAction action) => action switch
    {
        AppAction { Target: var t } => t.Behavior == AppBehavior.Quit ? $"Quit {t.Name}" : t.Name,
        UrlAction u => HostLabel(u.Link.Url),
        FileAction f => f.Target.DisplayName.Length == 0 ? "File" : f.Target.DisplayName,
        KeystrokeAction k => k.Combo.DisplayString,
        MediaAction m => m.Command.Title(),
        ScreenshotAction s => s.Options.Title(),
        SystemAction s => s.Command.Title(),
        EditAction e => e.Command.Title(),
        WindowAction w => w.Command.Title(),
        ShortcutAction s => s.Shortcut.Name.Length == 0 ? "Shortcut" : s.Shortcut.Name,
        AppShortcutAction a => a.Shortcut.Title.Length == 0 ? $"{a.Shortcut.AppName} Shortcut" : a.Shortcut.Title,
        MenuItemAction m => m.Item.Path.Count == 0 ? "Menu Command" : m.Item.Path[^1],
        AppleScriptAction => "AppleScript",
        ShellAction s => s.Script.ShellTitle(),
        TextAction t => t.Snippet.Text.Length == 0 ? "Text" : Preview(t.Snippet.Text),
        AiPromptAction p => $"Ask {(p.Prompt.Service == AiService.Custom ? "AI" : p.Prompt.Service.DisplayName())}",
        FolderAction => "Folder",
        MacroAction m => m.Macro.Steps.Count == 0 ? "Smart Action" : $"Smart Action ({m.Macro.Steps.Count})",
        _ => "Action",
    };

    /// <summary>
    /// Symbol used when the slot has no custom icon. App actions draw the app's own icon instead
    /// (see <see cref="DefaultIcon"/>); this is their fallback.
    /// </summary>
    public static string DefaultSymbol(this HaloAction action) => action switch
    {
        AppAction => "app.dashed",
        UrlAction => "globe",
        FileAction f => f.Target.IsDirectory ? "folder.fill" : "doc.fill",
        KeystrokeAction => "command",
        MediaAction m => m.Command.Symbol(),
        ScreenshotAction s => s.Options.Mode.Symbol(),
        SystemAction s => s.Command.Symbol(),
        EditAction e => e.Command.Symbol(),
        WindowAction w => w.Command.Symbol(),
        ShortcutAction => "square.2.layers.3d.fill",
        AppShortcutAction a => a.Shortcut.Symbol ?? "command",
        MenuItemAction => "filemenu.and.selection",
        AppleScriptAction => "applescript.fill",
        ShellAction => "terminal.fill",
        TextAction => "text.cursor",
        AiPromptAction => "sparkles",
        FolderAction => "circle.grid.cross.fill",
        _ => "wand.and.stars",
    };

    /// <summary>The icon drawn by default.</summary>
    public static IconSpec DefaultIcon(this HaloAction action) =>
        action is AppAction app ? new AppIcon(app.Target.BundleId) : new SymbolIcon(action.DefaultSymbol());

    /// <summary>Whether the action can run on Windows (Mac-only kinds show as unavailable).</summary>
    public static ActionAvailability Availability(this HaloAction action) => action switch
    {
        AppleScriptAction => ActionAvailability.Unavailable("AppleScript runs only on the Mac."),
        ShortcutAction => ActionAvailability.Unavailable("Apple Shortcuts run only on the Mac."),
        MenuItemAction => ActionAvailability.Unavailable("Menu-bar commands run only on the Mac. Use an App Shortcut instead."),
        SystemAction { Command: SystemCommand.DoNotDisturb } =>
            ActionAvailability.Unavailable("Windows doesn't let apps switch Do Not Disturb. Use Quick Settings instead."),
        MacroAction m => m.Macro.Steps.Select(s => s.Action.Availability()).FirstOrDefault(a => !a.IsAvailable) is { } blocked
            ? ActionAvailability.Unavailable($"A step can't run on Windows: {blocked.Reason}")
            : ActionAvailability.Available,
        _ => ActionAvailability.Available,
    };

    /// <summary>The title a slot shows: custom title, else the action's default, else "Empty".</summary>
    public static string DisplayTitle(this Slot slot)
    {
        var custom = slot.Title?.Trim();
        if (!string.IsNullOrEmpty(custom)) return custom;
        return slot.Action?.DefaultTitle() ?? "Empty";
    }

    /// <summary>The icon a slot shows, or null for an empty slot.</summary>
    public static IconSpec? DisplayIcon(this Slot slot) => slot.Icon ?? slot.Action?.DefaultIcon();

    // Payload titles and symbols

    public static string Title(this MediaCommand command) => command switch
    {
        MediaCommand.PlayPause => "Play/Pause",
        MediaCommand.NextTrack => "Next Track",
        MediaCommand.PreviousTrack => "Previous Track",
        MediaCommand.VolumeUp => "Volume Up",
        MediaCommand.VolumeDown => "Volume Down",
        MediaCommand.Mute => "Mute",
        MediaCommand.BrightnessUp => "Brightness Up",
        _ => "Brightness Down",
    };

    public static string Symbol(this MediaCommand command) => command switch
    {
        MediaCommand.PlayPause => "playpause.fill",
        MediaCommand.NextTrack => "forward.fill",
        MediaCommand.PreviousTrack => "backward.fill",
        MediaCommand.VolumeUp => "speaker.wave.3.fill",
        MediaCommand.VolumeDown => "speaker.wave.1.fill",
        MediaCommand.Mute => "speaker.slash.fill",
        MediaCommand.BrightnessUp => "sun.max.fill",
        _ => "sun.min.fill",
    };

    /// <summary>Volume and brightness: the scroll wheel over the highlighted slot adjusts them.</summary>
    public static bool IsAdjustable(this MediaCommand command) => command.Adjusted(up: true) is not null;

    /// <summary>The up or down variant of an adjustable command, else null.</summary>
    public static MediaCommand? Adjusted(this MediaCommand command, bool up) => command switch
    {
        MediaCommand.VolumeUp or MediaCommand.VolumeDown => up ? MediaCommand.VolumeUp : MediaCommand.VolumeDown,
        MediaCommand.BrightnessUp or MediaCommand.BrightnessDown => up ? MediaCommand.BrightnessUp : MediaCommand.BrightnessDown,
        _ => null,
    };

    public static string Title(this ScreenshotOptions options) => options.Mode switch
    {
        ScreenshotMode.Area => options.ToClipboard ? "Copy Area" : "Snip Area",
        ScreenshotMode.Window => options.ToClipboard ? "Copy Window" : "Screenshot Window",
        ScreenshotMode.FullScreen => options.ToClipboard ? "Copy Screen" : "Screenshot",
        _ => "Snipping Tool",
    };

    public static string Symbol(this ScreenshotMode mode) => mode switch
    {
        ScreenshotMode.Area => "rectangle.dashed",
        ScreenshotMode.Window => "macwindow",
        ScreenshotMode.FullScreen => "display",
        _ => "camera.viewfinder",
    };

    public static string Title(this SystemCommand command) => command switch
    {
        SystemCommand.MissionControl => "Task View",
        SystemCommand.AppExpose => "Switch Windows",
        SystemCommand.ShowDesktop => "Show Desktop",
        SystemCommand.Launchpad => "Start",
        SystemCommand.NotificationCenter => "Notifications",
        SystemCommand.Spotlight => "Search",
        SystemCommand.Siri => "Copilot",
        SystemCommand.LockScreen => "Lock",
        SystemCommand.SleepDisplay => "Turn Off Display",
        SystemCommand.Sleep => "Sleep",
        SystemCommand.ScreenSaver => "Screen Saver",
        SystemCommand.EmojiPicker => "Emoji",
        SystemCommand.Dictation => "Voice Typing",
        SystemCommand.ToggleDarkMode => "Dark Mode",
        SystemCommand.DoNotDisturb => "Do Not Disturb",
        SystemCommand.ForceQuit => "Task Manager",
        SystemCommand.SystemSettings => "Settings",
        _ => "Quick Settings",
    };

    public static string Symbol(this SystemCommand command) => command switch
    {
        SystemCommand.MissionControl => "rectangle.3.group",
        SystemCommand.AppExpose => "rectangle.stack",
        SystemCommand.ShowDesktop => "menubar.dock.rectangle",
        SystemCommand.Launchpad => "square.grid.3x3.fill",
        SystemCommand.NotificationCenter => "bell.badge",
        SystemCommand.Spotlight => "magnifyingglass",
        SystemCommand.Siri => "waveform",
        SystemCommand.LockScreen => "lock.fill",
        SystemCommand.SleepDisplay => "moon.fill",
        SystemCommand.Sleep => "powersleep",
        SystemCommand.ScreenSaver => "sparkles.tv",
        SystemCommand.EmojiPicker => "face.smiling",
        SystemCommand.Dictation => "mic.fill",
        SystemCommand.ToggleDarkMode => "circle.lefthalf.filled",
        SystemCommand.DoNotDisturb => "moon.circle.fill",
        SystemCommand.ForceQuit => "xmark.octagon.fill",
        SystemCommand.SystemSettings => "gearshape.fill",
        _ => "switch.2",
    };

    public static string Title(this EditCommand command) => command switch
    {
        EditCommand.Copy => "Copy",
        EditCommand.Cut => "Cut",
        EditCommand.Paste => "Paste",
        EditCommand.PasteAndMatchStyle => "Paste as Plain Text",
        EditCommand.Undo => "Undo",
        EditCommand.Redo => "Redo",
        EditCommand.SelectAll => "Select All",
        _ => "Find",
    };

    public static string Symbol(this EditCommand command) => command switch
    {
        EditCommand.Copy => "doc.on.doc",
        EditCommand.Cut => "scissors",
        EditCommand.Paste => "doc.on.clipboard",
        EditCommand.PasteAndMatchStyle => "doc.plaintext",
        EditCommand.Undo => "arrow.uturn.backward",
        EditCommand.Redo => "arrow.uturn.forward",
        EditCommand.SelectAll => "selection.pin.in.out",
        _ => "text.magnifyingglass",
    };

    /// <summary>The standard Windows shortcut this command sends.</summary>
    public static KeyCombo KeyCombo(this EditCommand command) => command switch
    {
        EditCommand.Copy => new(VirtualKeys.C, Modifiers.Control, "C"),
        EditCommand.Cut => new(VirtualKeys.X, Modifiers.Control, "X"),
        EditCommand.Paste => new(VirtualKeys.V, Modifiers.Control, "V"),
        EditCommand.PasteAndMatchStyle => new(VirtualKeys.V, Modifiers.Control | Modifiers.Shift, "V"),
        EditCommand.Undo => new(VirtualKeys.Z, Modifiers.Control, "Z"),
        EditCommand.Redo => new(VirtualKeys.Y, Modifiers.Control, "Y"),
        EditCommand.SelectAll => new(VirtualKeys.A, Modifiers.Control, "A"),
        _ => new(VirtualKeys.F, Modifiers.Control, "F"),
    };

    public static string Title(this WindowCommand command) => command switch
    {
        WindowCommand.LeftHalf => "Snap Left",
        WindowCommand.RightHalf => "Snap Right",
        WindowCommand.TopHalf => "Top Half",
        WindowCommand.BottomHalf => "Bottom Half",
        WindowCommand.Maximize => "Maximize",
        WindowCommand.Center => "Center",
        WindowCommand.Minimize => "Minimize",
        WindowCommand.ToggleFullScreen => "Full Screen",
        WindowCommand.NextDisplay => "Next Monitor",
        _ => "Close Window",
    };

    public static string Symbol(this WindowCommand command) => command switch
    {
        WindowCommand.LeftHalf => "rectangle.lefthalf.filled",
        WindowCommand.RightHalf => "rectangle.righthalf.filled",
        WindowCommand.TopHalf => "rectangle.tophalf.filled",
        WindowCommand.BottomHalf => "rectangle.bottomhalf.filled",
        WindowCommand.Maximize => "rectangle.inset.filled",
        WindowCommand.Center => "rectangle.center.inset.filled",
        WindowCommand.Minimize => "minus.rectangle",
        WindowCommand.ToggleFullScreen => "arrow.up.left.and.arrow.down.right",
        WindowCommand.NextDisplay => "display.2",
        _ => "xmark.rectangle",
    };

    /// <summary>"PowerShell", "Command Prompt", or the shell's own name.</summary>
    public static string ShellTitle(this ScriptSource script) => script.Shell?.Trim().ToLowerInvariant() switch
    {
        null or "" or "powershell" or "powershell.exe" => "PowerShell",
        "pwsh" or "pwsh.exe" => "PowerShell 7",
        "cmd" or "cmd.exe" => "Command Prompt",
        _ => System.IO.Path.GetFileNameWithoutExtension(script.Shell!.Trim()),
    };

    private static string HostLabel(string url)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri)) return url.Length == 0 ? "Link" : url;
        if (!string.IsNullOrEmpty(uri.Host))
        {
            return uri.Host.StartsWith("www.", StringComparison.OrdinalIgnoreCase) ? uri.Host[4..] : uri.Host;
        }
        return $"{uri.Scheme} link";
    }

    private static string Preview(string text)
    {
        var firstLine = text.Split('\n', '\r').FirstOrDefault(l => l.Length > 0) ?? text;
        return firstLine.Length > 24 ? firstLine[..23] + "…" : firstLine;
    }
}
