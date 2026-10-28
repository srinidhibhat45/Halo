using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using static Halo.App.Interop.Native;

namespace Halo.App.Interop;

/// <summary>
/// A notification-area (tray) icon via <c>Shell_NotifyIconW</c>, owned by a hidden window that
/// receives its messages. Re-adds itself when Explorer restarts.
/// </summary>
internal sealed unsafe partial class TrayIcon : IDisposable
{
    private const uint CallbackMessage = WM_APP + 0x20;
    private const uint NIM_ADD = 0, NIM_MODIFY = 1, NIM_DELETE = 2, NIM_SETVERSION = 4;
    private const uint NIF_MESSAGE = 0x1, NIF_ICON = 0x2, NIF_TIP = 0x4, NIF_SHOWTIP = 0x80;
    private const uint NOTIFYICON_VERSION_4 = 4;
    private const uint NIN_SELECT = 0x400, NIN_KEYSELECT = 0x401;
    private const uint Id = 1;

    private readonly HwndSource _window;
    private readonly uint _taskbarCreated;
    private nint _icon;
    private string _tooltip;
    private bool _added;

    public TrayIcon(nint icon, string tooltip)
    {
        _icon = icon;
        _tooltip = tooltip;
        _taskbarCreated = RegisterWindowMessageW("TaskbarCreated");
        // A hidden top-level (not message-only) window: it can take the foreground so the menu
        // closes when the user clicks elsewhere.
        _window = new HwndSource(new HwndSourceParameters("Halo tray")
        {
            Width = 0,
            Height = 0,
            WindowStyle = unchecked((int)0x80000000),   // WS_POPUP
            ExtendedWindowStyle = (int)WS_EX_TOOLWINDOW,
        });
        _window.AddHook(WndProc);
    }

    /// <summary>Left click or Enter on the icon.</summary>
    public event Action? Invoked;

    /// <summary>Right click or the menu key; the handler shows a menu (call <see cref="PrepareForMenu"/> first).</summary>
    public event Action? MenuRequested;

    public nint WindowHandle => _window.Handle;

    public bool IsVisible
    {
        get => _added;
        set
        {
            if (value == _added) return;
            if (value) Add();
            else Remove();
        }
    }

    public void Update(nint icon, string tooltip)
    {
        _icon = icon;
        _tooltip = tooltip;
        if (!_added) return;
        var data = Data(NIF_ICON | NIF_TIP | NIF_SHOWTIP);
        Shell_NotifyIconW(NIM_MODIFY, &data);
    }

    /// <summary>Gives the owner window the foreground so a context menu dismisses normally.</summary>
    public void PrepareForMenu() => SetForegroundWindow(_window.Handle);

    public void Dispose()
    {
        Remove();
        _window.RemoveHook(WndProc);
        _window.Dispose();
    }

    private void Add()
    {
        var data = Data(NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP);
        _added = Shell_NotifyIconW(NIM_ADD, &data);
        if (!_added) return;
        data.uTimeoutOrVersion = NOTIFYICON_VERSION_4;
        Shell_NotifyIconW(NIM_SETVERSION, &data);
    }

    private void Remove()
    {
        if (!_added) return;
        var data = Data(0);
        Shell_NotifyIconW(NIM_DELETE, &data);
        _added = false;
    }

    private NOTIFYICONDATAW Data(uint flags)
    {
        var data = new NOTIFYICONDATAW
        {
            cbSize = (uint)sizeof(NOTIFYICONDATAW),
            hWnd = _window.Handle,
            uID = Id,
            uFlags = flags,
            uCallbackMessage = CallbackMessage,
            hIcon = _icon,
        };
        var tip = _tooltip.Length > 127 ? _tooltip[..127] : _tooltip;
        for (var i = 0; i < tip.Length; i++) data.szTip[i] = tip[i];
        return data;
    }

    private nint WndProc(nint hwnd, int msg, nint wParam, nint lParam, ref bool handled)
    {
        if ((uint)msg == _taskbarCreated && _added)
        {
            // Explorer restarted: the icon is gone.
            _added = false;
            Add();
        }
        else if ((uint)msg == CallbackMessage)
        {
            switch ((uint)(lParam & 0xFFFF))
            {
                case NIN_SELECT or NIN_KEYSELECT:
                    Invoked?.Invoke();
                    handled = true;
                    break;
                case WM_CONTEXTMENU:
                    MenuRequested?.Invoke();
                    handled = true;
                    break;
            }
        }
        return 0;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NOTIFYICONDATAW
    {
        public uint cbSize;
        public nint hWnd;
        public uint uID;
        public uint uFlags;
        public uint uCallbackMessage;
        public nint hIcon;
        public fixed char szTip[128];
        public uint dwState;
        public uint dwStateMask;
        public fixed char szInfo[256];
        public uint uTimeoutOrVersion;
        public fixed char szInfoTitle[64];
        public uint dwInfoFlags;
        public Guid guidItem;
        public nint hBalloonIcon;
    }

    [LibraryImport("shell32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool Shell_NotifyIconW(uint dwMessage, NOTIFYICONDATAW* lpData);
}

/// <summary>Creates icon handles from an <c>.ico</c> file's bytes at the size Windows wants.</summary>
internal static unsafe class IconFactory
{
    private const int SM_CXSMICON = 49;

    /// <summary>A small (tray-sized) icon for the current DPI. Free it with <see cref="Native.DestroyIcon"/>.</summary>
    public static nint SmallIcon(byte[] ico, uint dpi)
    {
        var size = GetSystemMetricsForDpi(SM_CXSMICON, dpi);
        return FromIco(ico, size <= 0 ? 16 : size);
    }

    /// <summary>The ico entry closest to (and not smaller than) <paramref name="size"/>, as an HICON.</summary>
    public static nint FromIco(byte[] ico, int size)
    {
        if (ico.Length < 6) return 0;
        int count = BitConverter.ToUInt16(ico, 4);
        var best = -1;
        var bestSize = int.MaxValue;
        var largest = -1;
        var largestSize = 0;
        for (var i = 0; i < count; i++)
        {
            var entry = 6 + i * 16;
            if (entry + 16 > ico.Length) break;
            var width = ico[entry] == 0 ? 256 : ico[entry];
            if (width >= size && width < bestSize) (best, bestSize) = (i, width);
            if (width > largestSize) (largest, largestSize) = (i, width);
        }
        var chosen = best >= 0 ? best : largest;
        if (chosen < 0) return 0;
        var offset = 6 + chosen * 16;
        var length = BitConverter.ToInt32(ico, offset + 8);
        var dataOffset = BitConverter.ToInt32(ico, offset + 12);
        if (dataOffset < 0 || length <= 0 || dataOffset + length > ico.Length) return 0;
        fixed (byte* p = &ico[dataOffset])
        {
            return CreateIconFromResourceEx(p, (uint)length, true, 0x00030000, size, size, 0);
        }
    }

    /// <summary>The bytes of a WPF resource (e.g. <c>Assets/Halo.ico</c>).</summary>
    public static byte[] ResourceBytes(string relativePath)
    {
        var info = Application.GetResourceStream(new Uri($"pack://application:,,,/{relativePath}", UriKind.Absolute));
        if (info is null) return [];
        using var stream = info.Stream;
        using var memory = new MemoryStream();
        stream.CopyTo(memory);
        return memory.ToArray();
    }
}
