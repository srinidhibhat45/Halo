using System.Runtime.InteropServices;
using Halo.App.Interop;
using Halo.Core;
using static Halo.App.Interop.Native;

namespace Halo.App.Actions;

/// <summary>
/// Moves, sizes and closes the window in front, within the work area of its monitor (physical
/// pixels). Window requests are posted asynchronously so a hung app can't stall Halo.
/// </summary>
internal static class WindowActions
{
    private const int ErrorAccessDenied = 5;
    private const uint MoveFlags = SWP_NOZORDER | SWP_NOACTIVATE | SWP_ASYNCWINDOWPOS;

    public static async Task<ActionOutcome> RunAsync(WindowCommand command, ActionContext context)
    {
        var window = context.TargetWindow;
        if (window == 0 || !IsWindow(window) || WindowTools.IsShellSurface(window)) return new ActionOutcome.Failed("There's no window in front to arrange.");

        switch (command)
        {
            case WindowCommand.Minimize:
                ShowWindowAsync(window, SW_MINIMIZE);
                return ActionOutcome.Done;
            case WindowCommand.Maximize:
                ShowWindowAsync(window, IsZoomed(window) ? SW_RESTORE : SW_MAXIMIZE);
                return ActionOutcome.Done;
            case WindowCommand.Close:
                PostMessageW(window, WM_SYSCOMMAND, SC_CLOSE, 0);
                return ActionOutcome.Done;
            case WindowCommand.ToggleFullScreen:
                await context.ReleaseTriggerModifiersAsync();
                KeySender.Send(VirtualKeys.F11);
                return ActionOutcome.Done;
            case WindowCommand.NextDisplay:
                return MoveToNextDisplay(window);
            default:
                return Arrange(window, command);
        }
    }

    /// <summary>Halves and centring on the window's own monitor.</summary>
    private static ActionOutcome Arrange(nint window, WindowCommand command)
    {
        if (IsZoomed(window)) ShowWindowAsync(window, SW_RESTORE);
        var work = Displays.Of(window).WorkArea;
        var visible = VisibleBounds(window);
        var (x, y, w, h) = command switch
        {
            WindowCommand.LeftHalf => (work.Left, work.Top, work.Width / 2, work.Height),
            WindowCommand.RightHalf => (work.Left + work.Width - work.Width / 2, work.Top, work.Width / 2, work.Height),
            WindowCommand.TopHalf => (work.Left, work.Top, work.Width, work.Height / 2),
            WindowCommand.BottomHalf => (work.Left, work.Top + work.Height - work.Height / 2, work.Width, work.Height / 2),
            _ => Centred(work, Math.Min(visible.Width, work.Width), Math.Min(visible.Height, work.Height)),
        };
        return MoveVisible(window, x, y, w, h);
    }

    /// <summary>Moves the window to the next monitor (left to right), keeping its relative place and size.</summary>
    private static ActionOutcome MoveToNextDisplay(nint window)
    {
        var displays = Displays.All();
        if (displays.Count < 2) return new ActionOutcome.Failed("There's only one monitor.");
        var current = Displays.Of(window);
        var index = displays.ToList().FindIndex(d => d.Handle == current.Handle);
        var next = displays[(index + 1) % displays.Count];
        var wasMaximized = IsZoomed(window);
        if (wasMaximized) ShowWindowAsync(window, SW_RESTORE);

        var from = current.WorkArea;
        var to = next.WorkArea;
        var visible = VisibleBounds(window);
        var sx = to.Width / (double)Math.Max(1, from.Width);
        var sy = to.Height / (double)Math.Max(1, from.Height);
        var w = (int)Math.Round(Math.Min(visible.Width * sx, to.Width));
        var h = (int)Math.Round(Math.Min(visible.Height * sy, to.Height));
        var x = to.Left + (int)Math.Round((visible.Left - from.Left) * sx);
        var y = to.Top + (int)Math.Round((visible.Top - from.Top) * sy);
        x = Math.Clamp(x, to.Left, to.Right - w);
        y = Math.Clamp(y, to.Top, to.Bottom - h);
        var outcome = MoveVisible(window, x, y, w, h);
        if (wasMaximized) ShowWindowAsync(window, SW_MAXIMIZE);
        return outcome;
    }

    /// <summary>Places the window so its visible frame (without the invisible resize borders) fills the rectangle.</summary>
    private static ActionOutcome MoveVisible(nint window, int x, int y, int width, int height)
    {
        GetWindowRect(window, out var outer);
        var visible = VisibleBounds(window);
        // Windows 10/11 frames have invisible borders: add them back around the visible rectangle.
        var left = visible.Left - outer.Left;
        var top = visible.Top - outer.Top;
        var right = outer.Right - visible.Right;
        var bottom = outer.Bottom - visible.Bottom;
        if (SetWindowPos(window, 0, x - left, y - top, width + left + right, height + top + bottom, MoveFlags)) return ActionOutcome.Done;
        return Marshal.GetLastPInvokeError() == ErrorAccessDenied
            ? new ActionOutcome.Failed("Halo can't move windows of apps running as administrator.")
            : new ActionOutcome.Failed("That window can't be moved.");
    }

    private static (int X, int Y, int W, int H) Centred(RECT work, int width, int height) =>
        (work.Left + (work.Width - width) / 2, work.Top + (work.Height - height) / 2, width, height);
}
