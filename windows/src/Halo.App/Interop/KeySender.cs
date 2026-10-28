using Halo.Core;
using static Halo.App.Interop.Native;

namespace Halo.App.Interop;

/// <summary>
/// Synthesises keyboard input with <c>SendInput</c>. Every event is tagged with
/// <see cref="InjectedTag"/> so Halo's own keyboard hook lets it through untouched.
/// </summary>
internal static class KeySender
{
    /// <summary>dwExtraInfo marker for events Halo injects ("HALO").</summary>
    public const nuint InjectedTag = 0x48414C4F;

    /// <summary>An unassigned virtual key, pressed to stop a lone Alt or Win release from opening a menu.</summary>
    private const ushort DummyKey = 0xE8;

    private static readonly (Modifiers Flag, ushort Vk)[] ModifierKeys =
    [
        (Modifiers.Command, VirtualKeys.LWin),
        (Modifiers.Control, VirtualKeys.LControl),
        (Modifiers.Option, VirtualKeys.LMenu),
        (Modifiers.Shift, VirtualKeys.LShift),
    ];

    /// <summary>Presses a key combination: modifiers down, key down and up, modifiers up.</summary>
    public static void Send(KeyCombo combo) => Send(combo.KeyCode, combo.Modifiers);

    public static void Send(ushort vk, Modifiers modifiers = Modifiers.None)
    {
        var inputs = new List<INPUT>();
        var mods = ModifierKeys.Where(m => modifiers.HasFlag(m.Flag)).Select(m => m.Vk).ToArray();
        foreach (var m in mods) inputs.Add(Key(m, up: false));
        inputs.Add(Key(vk, up: false));
        inputs.Add(Key(vk, up: true));
        foreach (var m in Enumerable.Reverse(mods)) inputs.Add(Key(m, up: true));
        Dispatch(inputs);
    }

    /// <summary>Presses and releases a lone key (e.g. the Windows key to open Start).</summary>
    public static void Tap(ushort vk) => Dispatch([Key(vk, up: false), Key(vk, up: true)]);

    /// <summary>Types text as Unicode characters (no layout dependence); newlines press Enter.</summary>
    public static void Type(string text)
    {
        var inputs = new List<INPUT>();
        for (var i = 0; i < text.Length; i++)
        {
            var c = text[i];
            if (c == '\r') continue;
            if (c == '\n' || c == '\t')
            {
                var vk = c == '\n' ? VirtualKeys.Return : VirtualKeys.Tab;
                inputs.Add(Key(vk, up: false));
                inputs.Add(Key(vk, up: true));
                continue;
            }
            inputs.Add(Unicode(c, up: false));
            inputs.Add(Unicode(c, up: true));
        }
        // Chunks keep each SendInput call short so other input can interleave on long snippets.
        foreach (var chunk in inputs.Chunk(64)) Dispatch(chunk);
    }

    /// <summary>Taps the dummy key: Windows then treats a following Alt/Win release as part of a
    /// shortcut instead of opening the Start menu or an app's menu bar.</summary>
    public static void TapDummy() => Tap(DummyKey);

    /// <summary>
    /// Releases (virtually) any of <paramref name="modifiers"/> still held, so synthesised shortcuts
    /// aren't combined with the user's fingers still on the trigger.
    /// </summary>
    public static void ReleaseHeld(Modifiers modifiers)
    {
        var inputs = new List<INPUT>();
        foreach (var (flag, vk) in ModifierKeys)
        {
            if (!modifiers.HasFlag(flag)) continue;
            foreach (var side in Sides(vk))
            {
                if (IsKeyDown(side)) inputs.Add(Key(side, up: true));
            }
        }
        if (inputs.Count > 0)
        {
            // Releasing Alt or Win alone would open a menu: press the dummy key first.
            inputs.InsertRange(0, [Key(DummyKey, up: false), Key(DummyKey, up: true)]);
            Dispatch(inputs);
        }
    }

    /// <summary>The modifiers of <paramref name="modifiers"/> that are physically held right now.</summary>
    public static Modifiers HeldModifiers(Modifiers modifiers)
    {
        var held = Modifiers.None;
        foreach (var (flag, vk) in ModifierKeys)
        {
            if (modifiers.HasFlag(flag) && Sides(vk).Any(side => IsKeyDown(side))) held |= flag;
        }
        return held;
    }

    /// <summary>
    /// Waits up to <paramref name="timeout"/> for the trigger's modifiers to be released (a user
    /// usually lets go a moment after choosing), then releases any still held.
    /// </summary>
    public static async Task WaitForModifiersReleasedAsync(Modifiers modifiers, TimeSpan timeout)
    {
        var deadline = Environment.TickCount64 + (long)timeout.TotalMilliseconds;
        while (HeldModifiers(modifiers) != Modifiers.None && Environment.TickCount64 < deadline)
        {
            await Task.Delay(15);
        }
        ReleaseHeld(modifiers);
    }

    private static ushort[] Sides(ushort leftVk) => leftVk switch
    {
        VirtualKeys.LWin => [VirtualKeys.LWin, VirtualKeys.RWin],
        VirtualKeys.LControl => [VirtualKeys.LControl, VirtualKeys.RControl],
        VirtualKeys.LMenu => [VirtualKeys.LMenu, VirtualKeys.RMenu],
        _ => [VirtualKeys.LShift, VirtualKeys.RShift],
    };

    private static INPUT Key(ushort vk, bool up)
    {
        var flags = up ? KEYEVENTF_KEYUP : 0;
        if (IsExtended(vk)) flags |= KEYEVENTF_EXTENDEDKEY;
        return new INPUT
        {
            type = INPUT_KEYBOARD,
            u = new INPUTUNION
            {
                ki = new KEYBDINPUT
                {
                    wVk = vk,
                    wScan = (ushort)MapVirtualKeyW(vk, MAPVK_VK_TO_VSC),
                    dwFlags = flags,
                    dwExtraInfo = InjectedTag,
                },
            },
        };
    }

    private static INPUT Unicode(char c, bool up) => new()
    {
        type = INPUT_KEYBOARD,
        u = new INPUTUNION
        {
            ki = new KEYBDINPUT
            {
                wScan = c,
                dwFlags = KEYEVENTF_UNICODE | (up ? KEYEVENTF_KEYUP : 0),
                dwExtraInfo = InjectedTag,
            },
        },
    };

    /// <summary>Keys that need KEYEVENTF_EXTENDEDKEY to be distinguished from their numpad twins.</summary>
    private static bool IsExtended(ushort vk) => vk is
        VirtualKeys.Left or VirtualKeys.Up or VirtualKeys.Right or VirtualKeys.Down or
        VirtualKeys.Home or VirtualKeys.End or VirtualKeys.PageUp or VirtualKeys.PageDown or
        VirtualKeys.Insert or VirtualKeys.Delete or VirtualKeys.Snapshot or
        VirtualKeys.LWin or VirtualKeys.RWin or VirtualKeys.Apps or VirtualKeys.RControl or VirtualKeys.RMenu or
        VirtualKeys.VolumeMute or VirtualKeys.VolumeDown or VirtualKeys.VolumeUp or
        VirtualKeys.MediaNextTrack or VirtualKeys.MediaPrevTrack or VirtualKeys.MediaStop or VirtualKeys.MediaPlayPause;

    private static unsafe void Dispatch(IReadOnlyCollection<INPUT> inputs)
    {
        if (inputs.Count == 0) return;
        var array = inputs as INPUT[] ?? inputs.ToArray();
        fixed (INPUT* p = array)
        {
            SendInput((uint)array.Length, p, sizeof(INPUT));
        }
    }
}
