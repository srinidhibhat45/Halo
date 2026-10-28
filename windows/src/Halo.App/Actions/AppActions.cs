using System.ComponentModel;
using Halo.App.Interop;
using Halo.Core;
using static Halo.App.Interop.Native;

namespace Halo.App.Actions;

/// <summary>Opening, toggling and closing apps, and sending an app its own shortcuts.</summary>
internal static class AppActions
{
    public static ActionOutcome Run(AppTarget target, ActionContext context)
    {
        if (target.BundleId.Length == 0 && string.IsNullOrWhiteSpace(target.Path)) return new ActionOutcome.Failed("Choose an app for this slot.");
        var matches = Matcher(target.BundleId, target.Path);
        var windows = WindowTools.WindowsOf(matches);
        switch (target.Behavior)
        {
            case AppBehavior.Quit:
                if (windows.Count == 0) return new ActionOutcome.Failed($"{target.Name} has no open windows.");
                foreach (var window in windows) PostMessageW(window, WM_SYSCOMMAND, SC_CLOSE, 0);
                return ActionOutcome.Done;
            case AppBehavior.Toggle when context.FrontApp is { } front && matches(front):
                foreach (var window in windows) ShowWindowAsync(window, SW_MINIMIZE);
                return ActionOutcome.Done;
            default:
                if (windows.Count > 0)
                {
                    WindowTools.Activate(windows[0]);
                    return ActionOutcome.Done;
                }
                return Launch(target);
        }
    }

    /// <summary>
    /// Sends an app its own shortcut: brings its window forward if another app is in front, sends
    /// the keys, and (for "bring forward and return") goes back to the window you were in.
    /// </summary>
    public static async Task<ActionOutcome> SendShortcutAsync(AppShortcut shortcut, ActionContext context)
    {
        if (shortcut.BundleId.Length == 0) return new ActionOutcome.Failed("Choose an app for this shortcut.");
        var matches = Matcher(shortcut.BundleId, null);
        var windows = WindowTools.WindowsOf(matches);
        if (windows.Count == 0) return new ActionOutcome.Failed($"{shortcut.AppName} isn't open.");

        await context.ReleaseTriggerModifiersAsync();
        var previous = context.TargetWindow;
        var target = windows[0];
        var alreadyInFront = WindowTools.IdentityOf(GetForegroundWindow()) is { } front && matches(front);
        if (!alreadyInFront)
        {
            WindowTools.Activate(target);
            if (!await WaitForForegroundAsync(target)) return new ActionOutcome.Failed($"Couldn't bring {shortcut.AppName} forward.");
        }
        KeySender.Send(shortcut.Combo);
        if (shortcut.Delivery == AppDelivery.BringToFrontAndReturn && !alreadyInFront && previous != 0 && previous != target)
        {
            // Let the app handle the keys before it loses focus.
            await Task.Delay(150);
            WindowTools.Activate(previous);
        }
        return ActionOutcome.Confirmed;
    }

    /// <summary>Whether a running app is the one an action names (exe name, AppUserModelID, or the exe behind a path).</summary>
    public static Func<AppIdentity, bool> Matcher(string bundleId, string? path)
    {
        var exeFromPath = ExecutableName(path);
        return identity =>
            (bundleId.Length > 0 && identity.Matches(bundleId))
            || (exeFromPath is not null && string.Equals(identity.ExeName, exeFromPath, StringComparison.OrdinalIgnoreCase));
    }

    private static ActionOutcome Launch(AppTarget target)
    {
        try
        {
            var path = string.IsNullOrWhiteSpace(target.Path) ? null : PathExpansion.Expand(target.Path);
            if (path is not null && (File.Exists(path) || path.StartsWith("shell:", StringComparison.OrdinalIgnoreCase)))
            {
                ShellLauncher.Open(path);
            }
            else if (target.BundleId.Contains('!'))
            {
                ShellLauncher.OpenPackagedApp(target.BundleId);
            }
            else
            {
                // An executable name: ShellExecute finds registered apps ("chrome.exe", "notepad.exe").
                ShellLauncher.Open(ShellLauncher.ResolveExecutable(target.BundleId));
            }
            // Let the new app take the foreground even though Halo itself never activates.
            AllowSetForegroundWindow(uint.MaxValue);
            return ActionOutcome.Done;
        }
        catch (Win32Exception)
        {
            return new ActionOutcome.Failed($"Couldn't open {target.Name}. It may have been moved or uninstalled.");
        }
    }

    private static async Task<bool> WaitForForegroundAsync(nint window)
    {
        var deadline = Environment.TickCount64 + 600;
        while (GetForegroundWindow() != window && Environment.TickCount64 < deadline) await Task.Delay(15);
        return GetForegroundWindow() == window;
    }

    /// <summary>The executable name behind a launch path: the exe itself, or a shortcut's target.</summary>
    private static string? ExecutableName(string? path)
    {
        if (string.IsNullOrWhiteSpace(path)) return null;
        var expanded = PathExpansion.Expand(path);
        if (expanded.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) return Path.GetFileName(expanded);
        if (expanded.EndsWith(".lnk", StringComparison.OrdinalIgnoreCase) && ShellItems.ShortcutTarget(expanded) is { } target)
        {
            return Path.GetFileName(target);
        }
        return null;
    }
}
