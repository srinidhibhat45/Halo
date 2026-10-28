using Halo.App.Interop;
using Halo.Core;

namespace Halo.App.Trigger;

/// <summary>Human labels for virtual keys, using the current keyboard layout where it matters.</summary>
internal static unsafe class KeyLabels
{
    private const uint MapVkToChar = 2;

    /// <summary>"H", "F5", "Space", "/"… for <paramref name="vk"/> on the current layout.</summary>
    public static string Label(ushort vk)
    {
        if (VirtualKeys.Label(vk) is { } fixedLabel) return fixedLabel;
        var ch = Native.MapVirtualKeyW(vk, MapVkToChar) & 0x7FFF;
        if (ch > 0x20) return char.ToUpperInvariant((char)ch).ToString();
        var scan = Native.MapVirtualKeyW(vk, Native.MAPVK_VK_TO_VSC);
        var buffer = stackalloc char[64];
        var length = Native.GetKeyNameTextW((int)(scan << 16), buffer, 64);
        return length > 0 ? new string(buffer, 0, length) : $"Key {vk}";
    }

    /// <summary>Why a recorded combo can't or shouldn't be the trigger, or null when it is fine.</summary>
    /// <param name="isError">True when the combo is refused outright.</param>
    public static string? Problem(KeyCombo combo, out bool isError)
    {
        isError = false;
        var m = combo.Modifiers & ~Modifiers.Function;
        var isFunctionKey = combo.KeyCode is >= VirtualKeys.F1 and <= VirtualKeys.F24;
        if ((m & (Modifiers.Control | Modifiers.Option | Modifiers.Command)) == 0 && !isFunctionKey)
        {
            isError = true;
            return "Use Ctrl, Alt or the Windows key (Shift alone isn't enough), or a function key.";
        }
        var isLock = m == Modifiers.Command && combo.KeyCode == 0x4C;   // Win+L
        var isSecureAttention = m == (Modifiers.Control | Modifiers.Option) && combo.KeyCode == VirtualKeys.Delete;
        if (isLock || isSecureAttention)
        {
            isError = true;
            return "Windows reserves this shortcut.";
        }
        if (IsCommonShortcut(m, combo.KeyCode))
        {
            return "Apps use this shortcut; while Halo has it, they won't get it.";
        }
        if (m == Modifiers.Option || m == (Modifiers.Option | Modifiers.Shift))
        {
            return "Alt shortcuts can clash with app menus and typing accents.";
        }
        return null;
    }

    private static bool IsCommonShortcut(Modifiers m, ushort vk) =>
        (m == Modifiers.Control && vk is VirtualKeys.C or VirtualKeys.V or VirtualKeys.X or VirtualKeys.Z or VirtualKeys.Y
            or VirtualKeys.A or VirtualKeys.S or VirtualKeys.F or VirtualKeys.N or VirtualKeys.T)
        || (m == Modifiers.Option && vk is VirtualKeys.Tab or 0x73 /* F4 */)
        || (m == Modifiers.Command && vk is VirtualKeys.D or VirtualKeys.Tab or 0x45 /* E */ or 0x52 /* R */ or VirtualKeys.S or VirtualKeys.A or VirtualKeys.N)
        || (m == (Modifiers.Control | Modifiers.Shift) && vk == VirtualKeys.Escape);
}
