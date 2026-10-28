namespace Halo.Core;

/// <summary>
/// The kinds of action a slot can hold. Serialised in camelCase ("app", "appleScript", "aiPrompt"…),
/// exactly as the macOS app writes them.
/// </summary>
public enum ActionKind
{
    App, Url, File, Keystroke, Media, Screenshot, System, Edit, Window,
    Shortcut, AppShortcut, MenuItem, AppleScript, Shell, Text, AiPrompt, Folder, Macro,
}

/// <summary>
/// What a ring slot does when chosen. One sealed record per <see cref="ActionKind"/>, each carrying
/// its payload, so <c>switch</c> expressions over actions are exhaustive by type.
/// </summary>
/// <remarks>
/// Encoded as <c>{"type": "&lt;kind&gt;", "value": {…payload}}</c> (see <see cref="Serialization.HaloJson"/>),
/// so a single unknown or broken action never invalidates a whole config.
/// </remarks>
public abstract record HaloAction
{
    private protected HaloAction() { }

    public abstract ActionKind Kind { get; }

    public bool IsFolder => Kind == ActionKind.Folder;
}

public sealed record AppAction(AppTarget Target) : HaloAction
{
    public override ActionKind Kind => ActionKind.App;
}

public sealed record UrlAction(WebLink Link) : HaloAction
{
    public override ActionKind Kind => ActionKind.Url;
}

public sealed record FileAction(FileTarget Target) : HaloAction
{
    public override ActionKind Kind => ActionKind.File;
}

public sealed record KeystrokeAction(KeyCombo Combo) : HaloAction
{
    public override ActionKind Kind => ActionKind.Keystroke;
}

public sealed record MediaAction(MediaCommand Command) : HaloAction
{
    public override ActionKind Kind => ActionKind.Media;
}

public sealed record ScreenshotAction(ScreenshotOptions Options) : HaloAction
{
    public override ActionKind Kind => ActionKind.Screenshot;
}

public sealed record SystemAction(SystemCommand Command) : HaloAction
{
    public override ActionKind Kind => ActionKind.System;
}

public sealed record EditAction(EditCommand Command) : HaloAction
{
    public override ActionKind Kind => ActionKind.Edit;
}

public sealed record WindowAction(WindowCommand Command) : HaloAction
{
    public override ActionKind Kind => ActionKind.Window;
}

/// <summary>An Apple Shortcut. Kept so Mac configs round-trip; it cannot run on Windows.</summary>
public sealed record ShortcutAction(ShortcutRef Shortcut) : HaloAction
{
    public override ActionKind Kind => ActionKind.Shortcut;
}

/// <summary>One app's own keyboard shortcut, sent to that app even while another app is in front.</summary>
public sealed record AppShortcutAction(AppShortcut Shortcut) : HaloAction
{
    public override ActionKind Kind => ActionKind.AppShortcut;
}

/// <summary>A command in an app's menu bar. Kept so Mac configs round-trip; it cannot run on Windows.</summary>
public sealed record MenuItemAction(MenuItemRef Item) : HaloAction
{
    public override ActionKind Kind => ActionKind.MenuItem;
}

/// <summary>An AppleScript. Kept so Mac configs round-trip; it cannot run on Windows.</summary>
public sealed record AppleScriptAction(ScriptSource Script) : HaloAction
{
    public override ActionKind Kind => ActionKind.AppleScript;
}

/// <summary>A shell script: Windows PowerShell by default, or the shell named in <see cref="ScriptSource.Shell"/>.</summary>
public sealed record ShellAction(ScriptSource Script) : HaloAction
{
    public override ActionKind Kind => ActionKind.Shell;
}

public sealed record TextAction(TextSnippet Snippet) : HaloAction
{
    public override ActionKind Kind => ActionKind.Text;
}

public sealed record AiPromptAction(AiPrompt Prompt) : HaloAction
{
    public override ActionKind Kind => ActionKind.AiPrompt;
}

/// <summary>A nested ring. The slot's title and icon name the folder.</summary>
public sealed record FolderAction(Ring Ring) : HaloAction
{
    public override ActionKind Kind => ActionKind.Folder;
}

/// <summary>A multi-step "Smart Action".</summary>
public sealed record MacroAction(Macro Macro) : HaloAction
{
    public override ActionKind Kind => ActionKind.Macro;
}
