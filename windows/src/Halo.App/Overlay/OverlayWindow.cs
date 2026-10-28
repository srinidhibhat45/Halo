using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using Halo.App.Interop;
using static Halo.App.Interop.Native;

namespace Halo.App.Overlay;

/// <summary>
/// The borderless, transparent, always-on-top window the ring is drawn in. It never activates (the
/// app in front keeps focus, so synthesised shortcuts land there), never shows in the taskbar or
/// Alt+Tab, and lets clicks through wherever the controller says the pointer isn't over the ring.
/// </summary>
/// <remarks>
/// Positioned in physical pixels with <c>SetWindowPos</c>; under per-monitor DPI awareness WPF
/// rescales the content when the window lands on a monitor with another scale.
/// </remarks>
internal sealed class OverlayWindow : Window
{
    private bool _clickThrough;

    public OverlayWindow(FrameworkElement content)
    {
        Title = "Halo ring";
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        ShowActivated = false;
        Topmost = true;
        Focusable = false;
        SizeToContent = SizeToContent.Manual;
        Content = content;
        SourceInitialized += (_, _) => ConfigureNativeWindow();
    }

    public nint Handle => new WindowInteropHelper(this).Handle;

    /// <summary>
    /// Makes the window ignore the mouse (clicks reach the app below) or take it. Toggled every frame
    /// from geometry, so clicks between bubbles still count as ring clicks.
    /// </summary>
    public bool ClickThrough
    {
        get => _clickThrough;
        set
        {
            if (_clickThrough == value || Handle == 0) return;
            _clickThrough = value;
            var style = (long)GetWindowLongPtrW(Handle, GWL_EXSTYLE);
            style = value ? style | WS_EX_TRANSPARENT : style & ~WS_EX_TRANSPARENT;
            SetWindowLongPtrW(Handle, GWL_EXSTYLE, (nint)style);
        }
    }

    /// <summary>Creates the native window off screen and renders once, so the first real show is instant.</summary>
    public void Prewarm()
    {
        new WindowInteropHelper(this).EnsureHandle();
        Place(-32000, -32000, 64, 64);
        Opacity = 0;
        Show();
        Hide();
        Opacity = 1;
    }

    /// <summary>Moves and sizes the window (physical pixels) and shows it without activating it.</summary>
    public void ShowAt(int x, int y, int width, int height)
    {
        // Move first so a DPI change (and WPF's rescale) happens before the final size is set.
        SetWindowPos(Handle, HWND_TOPMOST, x, y, 0, 0, SWP_NOSIZE | SWP_NOACTIVATE);
        Place(x, y, width, height);
        if (!IsVisible) Show();
        // Re-assert the exact rectangle after any WM_DPICHANGED adjustment.
        Place(x, y, width, height);
    }

    private void Place(int x, int y, int width, int height) =>
        SetWindowPos(Handle, HWND_TOPMOST, x, y, width, height, SWP_NOACTIVATE);

    private void ConfigureNativeWindow()
    {
        var hwnd = Handle;
        var style = (long)GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
        style |= WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_LAYERED;
        SetWindowLongPtrW(hwnd, GWL_EXSTYLE, (nint)style);
        SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_FRAMECHANGED);
        HwndSource.FromHwnd(hwnd)?.AddHook(WndProc);
    }

    private static nint WndProc(nint hwnd, int msg, nint wParam, nint lParam, ref bool handled)
    {
        if ((uint)msg == WM_MOUSEACTIVATE)
        {
            handled = true;
            return MA_NOACTIVATE;
        }
        return 0;
    }
}
