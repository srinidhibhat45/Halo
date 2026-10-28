using System.Diagnostics;
using System.Runtime.InteropServices;
using static Halo.App.Interop.Native;

namespace Halo.App.Interop;

/// <summary>A keyboard event seen by the low-level hook.</summary>
/// <param name="IsDown">Key down (including auto-repeat) rather than key up.</param>
/// <param name="IsOwnInjection">Injected by Halo itself (<see cref="KeySender.InjectedTag"/>).</param>
/// <param name="Time">Seconds on <see cref="HaloClock"/>.</param>
internal readonly record struct KeyEvent(ushort Vk, bool IsDown, bool IsOwnInjection, double Time);

/// <summary>A mouse button press seen by the low-level hook (physical screen pixels).</summary>
internal readonly record struct MouseDownEvent(int X, int Y, double Time);

/// <summary>Monotonic seconds shared by the hook, the overlay and the interaction state machine.</summary>
internal static class HaloClock
{
    public static double Now => Stopwatch.GetTimestamp() / (double)Stopwatch.Frequency;
}

/// <summary>
/// A dedicated thread that owns Halo's low-level keyboard hook (always on) and mouse hook (only
/// while the ring is open), with its own message loop.
/// </summary>
/// <remarks>
/// Low-level hooks run on the installing thread for every key and click system-wide, so they live
/// here rather than on the UI thread: a busy UI can never delay typing or get the hook removed by
/// Windows' hook timeout. The filters run on this thread, must return quickly and must not block;
/// they decide synchronously whether to swallow the event and hand everything else to the UI
/// thread asynchronously. Hooks are removed when the thread exits (<see cref="Dispose"/>).
/// </remarks>
internal sealed unsafe class HookThread : IDisposable
{
    private const uint MsgMouseHookOn = WM_APP + 1;
    private const uint MsgMouseHookOff = WM_APP + 2;
    private const uint MsgTapDummy = WM_APP + 3;

    /// <summary>The one running hook thread; the static hook procedures dispatch to it.</summary>
    private static HookThread? s_current;

    private readonly Thread _thread;
    private readonly ManualResetEventSlim _started = new();
    private readonly Func<KeyEvent, bool> _keyboardFilter;
    private readonly Action<MouseDownEvent> _mouseDown;
    private uint _threadId;
    private nint _keyboardHook;
    private nint _mouseHook;
    private bool _disposed;

    /// <param name="keyboardFilter">Called on the hook thread for every key event; return true to swallow it.</param>
    /// <param name="mouseDown">Called on the hook thread for every button press while the mouse hook is on; never swallows.</param>
    public HookThread(Func<KeyEvent, bool> keyboardFilter, Action<MouseDownEvent> mouseDown)
    {
        if (s_current is not null) throw new InvalidOperationException("Only one hook thread may run.");
        _keyboardFilter = keyboardFilter;
        _mouseDown = mouseDown;
        s_current = this;
        _thread = new Thread(Run) { IsBackground = true, Name = "Halo input hooks" };
        _thread.Start();
        _started.Wait();
    }

    /// <summary>False if Windows refused the keyboard hook (the trigger can't work).</summary>
    public bool IsKeyboardHookInstalled => _keyboardHook != 0;

    /// <summary>Turns the click-anywhere hook on while the ring is open, off otherwise.</summary>
    public void SetMouseHook(bool enabled) => Post(enabled ? MsgMouseHookOn : MsgMouseHookOff);

    /// <summary>
    /// Taps the dummy key from the hook thread, right after the event being filtered: used when the
    /// trigger includes Alt or Win so their release doesn't open a menu or Start.
    /// </summary>
    public void TapDummyKeyAfterCurrentEvent() => Post(MsgTapDummy);

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        Post(WM_QUIT);
        _thread.Join(TimeSpan.FromSeconds(2));
        s_current = null;
        _started.Dispose();
    }

    private void Post(uint message)
    {
        if (_threadId != 0) PostThreadMessageW(_threadId, message, 0, 0);
    }

    private void Run()
    {
        _threadId = GetCurrentThreadId();
        var module = GetModuleHandleW(null);
        _keyboardHook = SetWindowsHookExW(WH_KEYBOARD_LL, &KeyboardProc, module, 0);
        _started.Set();
        try
        {
            while (GetMessageW(out var msg, 0, 0, 0) > 0)
            {
                switch (msg.message)
                {
                    case MsgMouseHookOn when _mouseHook == 0:
                        _mouseHook = SetWindowsHookExW(WH_MOUSE_LL, &MouseProc, module, 0);
                        break;
                    case MsgMouseHookOff when _mouseHook != 0:
                        UnhookWindowsHookEx(_mouseHook);
                        _mouseHook = 0;
                        break;
                    case MsgTapDummy:
                        KeySender.TapDummy();
                        break;
                }
            }
        }
        finally
        {
            if (_mouseHook != 0) UnhookWindowsHookEx(_mouseHook);
            if (_keyboardHook != 0) UnhookWindowsHookEx(_keyboardHook);
            _mouseHook = 0;
            _keyboardHook = 0;
        }
    }

    [UnmanagedCallersOnly]
    private static nint KeyboardProc(int code, nint wParam, nint lParam)
    {
        if (code >= 0 && s_current is { } hooks)
        {
            var data = *(KBDLLHOOKSTRUCT*)lParam;
            var message = (uint)wParam;
            var isDown = message is WM_KEYDOWN or WM_SYSKEYDOWN;
            var e = new KeyEvent((ushort)data.vkCode, isDown, data.dwExtraInfo == KeySender.InjectedTag, HaloClock.Now);
            try
            {
                if (hooks._keyboardFilter(e)) return 1;
            }
            catch (Exception ex)
            {
                // Never let an exception cross into Windows' input path.
                Trace.TraceError($"Keyboard hook filter failed: {ex}");
            }
        }
        return CallNextHookEx(0, code, wParam, lParam);
    }

    [UnmanagedCallersOnly]
    private static nint MouseProc(int code, nint wParam, nint lParam)
    {
        if (code >= 0 && s_current is { } hooks && (uint)wParam is WM_LBUTTONDOWN or WM_RBUTTONDOWN or WM_MBUTTONDOWN or WM_XBUTTONDOWN)
        {
            var data = *(MSLLHOOKSTRUCT*)lParam;
            try
            {
                hooks._mouseDown(new MouseDownEvent(data.pt.X, data.pt.Y, HaloClock.Now));
            }
            catch (Exception ex)
            {
                Trace.TraceError($"Mouse hook handler failed: {ex}");
            }
        }
        return CallNextHookEx(0, code, wParam, lParam);
    }
}
