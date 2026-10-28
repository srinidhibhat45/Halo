using System.Runtime.InteropServices;
using static Halo.App.Interop.Native;

namespace Halo.App.Interop;

/// <summary>Who an app is, as far as app rings and app actions are concerned.</summary>
/// <param name="ExeName">Executable file name, e.g. <c>chrome.exe</c>.</param>
/// <param name="Aumid">AppUserModelID for packaged (Store) apps, else null.</param>
internal sealed record AppIdentity(string ExeName, string? ExePath, string? Aumid, uint ProcessId)
{
    /// <summary>Ids an <see cref="Halo.Core.AppProfile"/> may use for this app, most specific first.</summary>
    public IReadOnlyCollection<string> Ids => Aumid is null ? [ExeName] : [Aumid, ExeName];

    public bool Matches(string bundleId) =>
        string.Equals(bundleId, ExeName, StringComparison.OrdinalIgnoreCase)
        || (Aumid is not null && string.Equals(bundleId, Aumid, StringComparison.OrdinalIgnoreCase));
}

/// <summary>Top-level windows, the processes behind them, and bringing them to the front.</summary>
internal static unsafe class WindowTools
{
    private const string FrameHost = "applicationframehost.exe";

    /// <summary>The app that owns <paramref name="hwnd"/>; for UWP apps hosted by ApplicationFrameHost, the hosted app.</summary>
    public static AppIdentity? IdentityOf(nint hwnd)
    {
        if (hwnd == 0) return null;
        GetWindowThreadProcessId(hwnd, out var pid);
        var identity = ProcessIdentity(pid);
        if (identity is null || !string.Equals(identity.ExeName, FrameHost, StringComparison.OrdinalIgnoreCase)) return identity;
        var hostedPid = HostedProcess(hwnd, pid);
        return hostedPid is { } hosted ? ProcessIdentity(hosted) ?? identity : identity;
    }

    public static AppIdentity? ProcessIdentity(uint pid)
    {
        var handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
        if (handle == 0) return null;
        try
        {
            var path = ImagePath(handle);
            if (path is null) return null;
            return new AppIdentity(Path.GetFileName(path), path, Aumid(handle), pid);
        }
        finally
        {
            CloseHandle(handle);
        }
    }

    /// <summary>
    /// Visible, unowned app windows in Z-order (front first), excluding the desktop, the taskbar,
    /// tool windows and windows hidden on other virtual desktops.
    /// </summary>
    public static IReadOnlyList<nint> AppWindows()
    {
        var windows = new List<nint>();
        var handle = GCHandle.Alloc(windows);
        try
        {
            EnumWindows(&CollectWindow, GCHandle.ToIntPtr(handle));
        }
        finally
        {
            handle.Free();
        }
        return windows.Where(IsAppWindow).ToArray();
    }

    /// <summary>App windows whose app matches <paramref name="matches"/>, front first.</summary>
    public static IReadOnlyList<nint> WindowsOf(Func<AppIdentity, bool> matches)
    {
        var cache = new Dictionary<uint, AppIdentity?>();
        return AppWindows().Where(hwnd =>
        {
            GetWindowThreadProcessId(hwnd, out var pid);
            if (!cache.TryGetValue(pid, out var identity)) cache[pid] = identity = IdentityOf(hwnd);
            return identity is not null && matches(identity);
        }).ToArray();
    }

    /// <summary>True for the desktop, the taskbars and other shell surfaces that aren't app windows.</summary>
    public static bool IsShellSurface(nint hwnd) =>
        hwnd == 0 || hwnd == GetShellWindow()
        || ClassName(hwnd) is "Progman" or "WorkerW" or "Shell_TrayWnd" or "Shell_SecondaryTrayWnd";

    /// <summary>
    /// Restores (if minimised) and brings a window to the front. Windows only lets the foreground
    /// process do this, so the call briefly attaches to the foreground thread's input queue.
    /// </summary>
    public static bool Activate(nint hwnd)
    {
        if (IsIconic(hwnd)) ShowWindowAsync(hwnd, SW_RESTORE);
        var foreground = GetForegroundWindow();
        if (foreground == hwnd) return true;
        var current = GetCurrentThreadId();
        var foregroundThread = foreground == 0 ? 0 : GetWindowThreadProcessId(foreground, out _);
        var attached = foregroundThread != 0 && foregroundThread != current && AttachThreadInput(current, foregroundThread, true);
        try
        {
            BringWindowToTop(hwnd);
            SetForegroundWindow(hwnd);
        }
        finally
        {
            if (attached) AttachThreadInput(current, foregroundThread, false);
        }
        return GetForegroundWindow() == hwnd;
    }

    private static bool IsAppWindow(nint hwnd)
    {
        if (!IsWindowVisible(hwnd) || GetWindow(hwnd, GW_OWNER) != 0 || IsCloaked(hwnd) || IsShellSurface(hwnd)) return false;
        var exStyle = (long)GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
        if ((exStyle & WS_EX_TOOLWINDOW) != 0) return false;
        return GetWindowTextLengthW(hwnd) > 0;
    }

    private static string? ImagePath(nint process)
    {
        var buffer = stackalloc char[1024];
        uint size = 1024;
        return QueryFullProcessImageNameW(process, 0, buffer, ref size) ? new string(buffer, 0, (int)size) : null;
    }

    private static string? Aumid(nint process)
    {
        var buffer = stackalloc char[256];
        uint length = 256;
        return GetApplicationUserModelId(process, ref length, buffer) == 0 && length > 1 ? new string(buffer, 0, (int)length - 1) : null;
    }

    /// <summary>The process of the first child window that isn't the frame host itself.</summary>
    private static uint? HostedProcess(nint frame, uint framePid)
    {
        var children = new List<nint>();
        var handle = GCHandle.Alloc(children);
        try
        {
            EnumChildWindows(frame, &CollectWindow, GCHandle.ToIntPtr(handle));
        }
        finally
        {
            handle.Free();
        }
        foreach (var child in children)
        {
            GetWindowThreadProcessId(child, out var pid);
            if (pid != framePid) return pid;
        }
        return null;
    }

    [UnmanagedCallersOnly]
    private static int CollectWindow(nint hwnd, nint lParam)
    {
        if (GCHandle.FromIntPtr(lParam).Target is List<nint> list) list.Add(hwnd);
        return 1;
    }
}
