using System.ComponentModel;
using System.Diagnostics;
using Halo.App.Apps;
using Halo.App.Interop;
using Halo.Core;

namespace Halo.App.Actions;

/// <summary>What an action runs against, captured when the ring opened.</summary>
/// <param name="ForegroundWindow">The window that was in front (actions apply to it).</param>
/// <param name="FrontApp">Its app, if known.</param>
/// <param name="Anchor">The ring's centre in physical screen pixels (toasts appear near it).</param>
/// <param name="Trigger">The trigger, so synthesised keys wait until its modifiers are released.</param>
/// <param name="OverlayWindow">Halo's own window, for system commands sent through a window.</param>
internal sealed record ActionContext(nint ForegroundWindow, AppIdentity? FrontApp, string SlotTitle, (int X, int Y) Anchor, KeyCombo? Trigger, nint OverlayWindow)
{
    /// <summary>The window an action should act on now: the one in front, unless that is the desktop or Halo.</summary>
    public nint TargetWindow
    {
        get
        {
            var now = Native.GetForegroundWindow();
            return now != 0 && now != OverlayWindow && !WindowTools.IsShellSurface(now) ? now : ForegroundWindow;
        }
    }

    /// <summary>Waits (briefly) for the trigger's modifiers to be released, then releases any still held.</summary>
    public Task ReleaseTriggerModifiersAsync() =>
        KeySender.WaitForModifiersReleasedAsync(Trigger?.Modifiers ?? Modifiers.None, TimeSpan.FromMilliseconds(300));
}

/// <summary>How an action went.</summary>
internal abstract record ActionOutcome
{
    private ActionOutcome() { }

    /// <param name="Confirm">The action has no visible effect (copy, media keys…): show a brief confirmation.</param>
    public sealed record Success(bool Confirm = false) : ActionOutcome;

    /// <summary>Done, with something worth telling the user ("Saved to Screenshots").</summary>
    public sealed record SuccessWithMessage(string Message) : ActionOutcome;

    public sealed record Failed(string Message) : ActionOutcome;

    public static ActionOutcome Done { get; } = new Success();
    public static ActionOutcome Confirmed { get; } = new Success(Confirm: true);
}

/// <summary>Opening things with the shell (files, folders, URLs, protocol links, apps).</summary>
internal static class ShellLauncher
{
    /// <summary>Opens a path, URL or <c>shell:</c> link with its default handler.</summary>
    /// <exception cref="Win32Exception">Nothing could open it.</exception>
    public static void Open(string target, string? arguments = null)
    {
        using var process = Process.Start(new ProcessStartInfo(target)
        {
            UseShellExecute = true,
            Arguments = arguments ?? "",
        });
    }

    /// <summary>Starts an executable with explicit arguments (no shell parsing).</summary>
    public static void Run(string exe, params string[] arguments)
    {
        var info = new ProcessStartInfo(exe) { UseShellExecute = false };
        foreach (var argument in arguments) info.ArgumentList.Add(argument);
        using var process = Process.Start(info);
    }

    /// <summary>Launches a packaged app by its AppUserModelID.</summary>
    public static void OpenPackagedApp(string aumid) => Run("explorer.exe", $@"shell:AppsFolder\{aumid}");

    /// <summary>Resolves "chrome.exe" or a path to something startable: the path itself, or a registered app path.</summary>
    public static string ResolveExecutable(string nameOrPath)
    {
        var expanded = PathExpansion.Expand(nameOrPath);
        if (File.Exists(expanded)) return expanded;
        return AppIconCache.AppPath(Path.GetFileName(expanded)) ?? expanded;
    }
}
