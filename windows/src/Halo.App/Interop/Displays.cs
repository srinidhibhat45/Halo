using System.Runtime.InteropServices;
using static Halo.App.Interop.Native;

namespace Halo.App.Interop;

/// <summary>A display: its handle, full bounds and work area (physical pixels) and DPI scale.</summary>
internal sealed record Display(nint Handle, RECT Bounds, RECT WorkArea, double Scale);

/// <summary>Display enumeration and lookup.</summary>
internal static unsafe class Displays
{
    /// <summary>Every display, left to right then top to bottom.</summary>
    public static IReadOnlyList<Display> All()
    {
        var handles = new List<nint>();
        var gc = GCHandle.Alloc(handles);
        try
        {
            EnumDisplayMonitors(0, 0, &Collect, GCHandle.ToIntPtr(gc));
        }
        finally
        {
            gc.Free();
        }
        return handles.Select(From).OrderBy(m => m.Bounds.Left).ThenBy(m => m.Bounds.Top).ToArray();
    }

    /// <summary>The display containing the physical point (or the nearest one).</summary>
    public static Display At(int x, int y) => From(MonitorFromPoint(new POINT { X = x, Y = y }, MONITOR_DEFAULTTONEAREST));

    /// <summary>The display a window is (mostly) on.</summary>
    public static Display Of(nint hwnd) => From(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST));

    /// <summary>The pointer position in physical screen pixels.</summary>
    public static (int X, int Y) Cursor()
    {
        GetCursorPos(out var p);
        return (p.X, p.Y);
    }

    private static Display From(nint handle)
    {
        var info = MonitorInfo(handle);
        return new Display(handle, info.rcMonitor, info.rcWork, MonitorScale(handle));
    }

    [UnmanagedCallersOnly]
    private static int Collect(nint monitor, nint hdc, RECT* rect, nint data)
    {
        if (GCHandle.FromIntPtr(data).Target is List<nint> list) list.Add(monitor);
        return 1;
    }
}
