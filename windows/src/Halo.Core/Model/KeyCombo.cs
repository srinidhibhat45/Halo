namespace Halo.Core;

/// <summary>
/// Modifier keys, stored with the macOS app's bit values so configs are shared. On Windows
/// <see cref="Option"/> is Alt and <see cref="Command"/> is the Windows key.
/// </summary>
[Flags]
public enum Modifiers : byte
{
    None = 0,
    Control = 1 << 0,
    /// <summary>Alt on Windows (⌥ on the Mac).</summary>
    Option = 1 << 1,
    Shift = 1 << 2,
    /// <summary>The Windows key (⌘ on the Mac).</summary>
    Command = 1 << 3,
    Function = 1 << 4,
}

public static class ModifiersExtensions
{
    /// <summary>Key-cap names in Windows order: Win, Ctrl, Shift, Alt (Fn first when present).</summary>
    public static IReadOnlyList<string> KeyNames(this Modifiers modifiers) =>
        Names(modifiers, ("Fn", Modifiers.Function), ("Win", Modifiers.Command), ("Ctrl", Modifiers.Control),
              ("Shift", Modifiers.Shift), ("Alt", Modifiers.Option));

    /// <summary>Spoken names, e.g. "Windows Control Shift".</summary>
    public static IReadOnlyList<string> SpokenNames(this Modifiers modifiers) =>
        Names(modifiers, ("Function", Modifiers.Function), ("Windows", Modifiers.Command), ("Control", Modifiers.Control),
              ("Shift", Modifiers.Shift), ("Alt", Modifiers.Option));

    private static IReadOnlyList<string> Names(Modifiers modifiers, params (string Name, Modifiers Flag)[] order) =>
        order.Where(o => modifiers.HasFlag(o.Flag)).Select(o => o.Name).ToArray();
}

/// <summary>
/// A key plus modifiers. On Windows <see cref="KeyCode"/> is a virtual-key code (VK_*);
/// <see cref="KeyLabel"/> caches what the key showed when it was recorded ("H", "Space", "F5").
/// </summary>
public sealed record KeyCombo(ushort KeyCode, Modifiers Modifiers, string KeyLabel)
{
    /// <summary>The default ring trigger: Ctrl+Shift+Alt+H ("H" for Halo), the Windows twin of the Mac's ⌃⇧⌘H.</summary>
    public static KeyCombo DefaultTrigger { get; } = new(VirtualKeys.H, Modifiers.Control | Modifiers.Shift | Modifiers.Option, "H");

    /// <summary>e.g. "Ctrl+Shift+Alt+H".</summary>
    public string DisplayString => string.Join("+", Modifiers.KeyNames().Append(KeyLabel));

    /// <summary>e.g. "Control Shift Alt H".</summary>
    public string AccessibilityLabel => string.Join(" ", Modifiers.SpokenNames().Append(KeyLabel));
}

/// <summary>Windows virtual-key codes used by defaults, presets, the trigger and actions.</summary>
public static class VirtualKeys
{
    public const ushort Back = 0x08, Tab = 0x09, Return = 0x0D, Shift = 0x10, Control = 0x11, Menu = 0x12;
    public const ushort Pause = 0x13, CapsLock = 0x14, Escape = 0x1B, Space = 0x20;
    public const ushort PageUp = 0x21, PageDown = 0x22, End = 0x23, Home = 0x24;
    public const ushort Left = 0x25, Up = 0x26, Right = 0x27, Down = 0x28;
    public const ushort Snapshot = 0x2C, Insert = 0x2D, Delete = 0x2E;
    public const ushort D0 = 0x30, D1 = 0x31, D9 = 0x39;
    public const ushort A = 0x41, C = 0x43, D = 0x44, F = 0x46, H = 0x48, N = 0x4E, S = 0x53, T = 0x54, V = 0x56, X = 0x58, Y = 0x59, Z = 0x5A;
    public const ushort LWin = 0x5B, RWin = 0x5C, Apps = 0x5D;
    public const ushort NumPad0 = 0x60, NumPad9 = 0x69;
    public const ushort F1 = 0x70, F11 = 0x7A, F24 = 0x87;
    public const ushort LShift = 0xA0, RShift = 0xA1, LControl = 0xA2, RControl = 0xA3, LMenu = 0xA4, RMenu = 0xA5;
    public const ushort VolumeMute = 0xAD, VolumeDown = 0xAE, VolumeUp = 0xAF;
    public const ushort MediaNextTrack = 0xB0, MediaPrevTrack = 0xB1, MediaStop = 0xB2, MediaPlayPause = 0xB3;
    public const ushort OemPeriod = 0xBE;

    /// <summary>True for Shift, Ctrl, Alt and Windows keys (either side).</summary>
    public static bool IsModifier(ushort vk) => vk is Shift or Control or Menu or LWin or RWin
        or LShift or RShift or LControl or RControl or LMenu or RMenu;

    /// <summary>The modifier flag a modifier key sets, or <see cref="Modifiers.None"/>.</summary>
    public static Modifiers ModifierFlag(ushort vk) => vk switch
    {
        Shift or LShift or RShift => Modifiers.Shift,
        Control or LControl or RControl => Modifiers.Control,
        Menu or LMenu or RMenu => Modifiers.Option,
        LWin or RWin => Modifiers.Command,
        _ => Modifiers.None,
    };

    /// <summary>The digit (0–9) of a top-row digit key, or null.</summary>
    public static int? TopRowDigit(ushort vk) => vk is >= D0 and <= D9 ? vk - D0 : null;

    /// <summary>The digit (0–9) of a numeric-keypad key, or null.</summary>
    public static int? KeypadDigit(ushort vk) => vk is >= NumPad0 and <= NumPad9 ? vk - NumPad0 : null;

    /// <summary>
    /// A label for keys whose label does not depend on the keyboard layout (letters, digits,
    /// function and navigation keys), or null for layout-dependent keys.
    /// </summary>
    public static string? Label(ushort vk) => vk switch
    {
        >= A and <= Z or >= D0 and <= D9 => ((char)vk).ToString(),
        >= F1 and <= F24 => $"F{vk - F1 + 1}",
        >= NumPad0 and <= NumPad9 => $"Num {vk - NumPad0}",
        Back => "Backspace",
        Tab => "Tab",
        Return => "Enter",
        Escape => "Esc",
        Space => "Space",
        PageUp => "Page Up",
        PageDown => "Page Down",
        End => "End",
        Home => "Home",
        Left => "←",
        Up => "↑",
        Right => "→",
        Down => "↓",
        Snapshot => "Print Screen",
        Insert => "Insert",
        Delete => "Delete",
        Pause => "Pause",
        Apps => "Menu",
        _ => null,
    };
}
