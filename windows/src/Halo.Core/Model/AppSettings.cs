namespace Halo.Core;

/// <summary>How the trigger shortcut picks an action.</summary>
public enum SelectionMode
{
    /// <summary>A quick tap keeps the ring open (click, press a number, or press the shortcut again
    /// on a highlighted slot); holding past the threshold selects on release.</summary>
    Auto,
    /// <summary>The ring stays open after the shortcut; releasing never selects.</summary>
    TapThenClick,
    /// <summary>Release selects the highlighted slot; releasing with nothing highlighted cancels.</summary>
    HoldAndRelease,
}

public enum RingTheme
{
    /// <summary>Round bubbles around a small hub, modelled on Logitech's Actions Ring.</summary>
    Classic,
    /// <summary>A frosted, segmented ring.</summary>
    Glass,
}

public enum LabelMode
{
    /// <summary>The highlighted slot's name appears (tooltip or hub).</summary>
    Hub,
    /// <summary>Every slot shows a small caption.</summary>
    Always,
    /// <summary>Icons only.</summary>
    None,
}

public enum RingPlacement
{
    /// <summary>Centred on the pointer (kept on screen).</summary>
    Cursor,
    /// <summary>Centred on the screen that contains the pointer.</summary>
    ScreenCenter,
}

/// <summary>An inclusive range of doubles.</summary>
public readonly record struct ValueRange(double Min, double Max)
{
    public double Clamp(double value) => double.IsNaN(value) ? Min : Math.Clamp(value, Min, Max);
}

/// <summary>
/// App-wide preferences. Decoding is tolerant: missing keys fall back to these defaults, so older
/// configs keep working when settings are added (see <see cref="Serialization.HaloJson"/>).
/// </summary>
public sealed record AppSettings
{
    public static readonly ValueRange HoldThresholdRange = new(0.15, 0.8);
    public static readonly ValueRange RingScaleRange = new(0.8, 1.4);
    public static readonly ValueRange AnimationSpeedRange = new(0.0, 2.0);

    /// <summary>The global shortcut that opens the ring; null when the user cleared it.</summary>
    public KeyCombo? Trigger { get; init; } = KeyCombo.DefaultTrigger;
    public SelectionMode SelectionMode { get; init; } = SelectionMode.Auto;
    /// <summary>Seconds the shortcut must be held before release counts as "hold" in <see cref="SelectionMode.Auto"/>.</summary>
    public double HoldThreshold { get; init; } = 0.28;
    public RingTheme Theme { get; init; } = RingTheme.Classic;
    /// <summary>0.8…1.4 multiplier on the theme's ring size.</summary>
    public double RingScale { get; init; } = 1.0;
    public LabelMode LabelMode { get; init; } = LabelMode.Hub;
    public RingPlacement Placement { get; init; } = RingPlacement.Cursor;
    /// <summary>0.5 (slow)…2 (fast); 0 disables animation. Windows' "Animation effects" switch always wins.</summary>
    public double AnimationSpeed { get; init; } = 1.0;
    public RingColor Accent { get; init; } = RingColor.FromPreset(RingColorPreset.Blue);
    /// <summary>Mac only (Force Touch trackpads); kept so shared configs round-trip.</summary>
    public bool HapticsEnabled { get; init; } = true;
    public bool SoundsEnabled { get; init; }
    /// <summary>On Windows: show the notification-area (tray) icon. JSON key: <c>showMenuBarIcon</c>.</summary>
    public bool ShowMenuBarIcon { get; init; } = true;
    /// <summary>On Windows: start with Windows. JSON key: <c>launchAtLogin</c>.</summary>
    public bool LaunchAtLogin { get; init; }
    /// <summary>Use app-specific rings when their app is in front.</summary>
    public bool AppRingsEnabled { get; init; } = true;
    /// <summary>Show the numbers 1–9 on slots while the ring is open.</summary>
    public bool ShowSlotNumbers { get; init; }
    /// <summary>Show a brief toast after actions with no visible effect (copy, media, toggles).</summary>
    public bool ShowConfirmations { get; init; } = true;
    /// <summary>The live ring shows only filled slots, evenly spaced (no gaps for empty slots).</summary>
    public bool ClosesGaps { get; init; } = true;
    /// <summary>Check GitHub Releases for a newer Halo on launch and daily.</summary>
    public bool ChecksForUpdates { get; init; } = true;
    public bool HasCompletedOnboarding { get; init; }
}
