using System.Diagnostics.CodeAnalysis;
using System.Windows.Media;
using Halo.Core;
using Halo.Core.Interaction;

namespace Halo.App.Rendering;

internal enum RingMode
{
    /// <summary>The real overlay: hover highlight, appear/dismiss, folders fan out.</summary>
    Live,
    /// <summary>The configurator canvas: one level at a time, selection, empty-slot "+" affordances.</summary>
    Editor,
    /// <summary>A static thumbnail (theme picker); no interaction.</summary>
    Preview,
}

/// <summary>How the current level arrived, so the renderer can animate folder navigation.</summary>
internal enum LevelChange
{
    /// <summary>A fresh root (the ring opened, or the editor switched rings).</summary>
    Reset,
    /// <summary>A folder opened.</summary>
    Push,
    /// <summary>Went back to the parent level.</summary>
    Pop,
}

/// <summary>The app whose ring is shown (hub badge).</summary>
internal sealed record AppBadge(string BundleId, string Name, ImageSource? Icon);

/// <summary>
/// Everything <see cref="RingCanvas"/> draws, for the live overlay and the configurator. The
/// owner mutates it and calls <see cref="NotifyChanged"/>; the canvas only reads it and animates
/// between states.
/// </summary>
internal sealed class RingViewModel
{
    private RingLevels _levels;

    public RingViewModel(RingMode mode, Ring ring, AppSettings settings)
    {
        Mode = mode;
        _levels = new RingLevels(ring);
        Apply(settings);
    }

    /// <summary>Raised after the owner changes state; the canvas re-targets its springs.</summary>
    public event Action? Changed;

    public RingMode Mode { get; }

    // Content

    /// <summary>The root ring and the folders entered (live), or just the ring shown (editor).</summary>
    public RingLevels Levels => _levels;

    public Ring Current => _levels.Current;

    /// <summary>Bumped on every level change, with <see cref="LastLevelChange"/> saying how.</summary>
    public int LevelVersion { get; private set; }

    public LevelChange LastLevelChange { get; private set; }

    public AppBadge? AppBadge { get; set; }

    /// <summary>Editor: slots of an app ring that show the Everywhere ring's action (drawn ghosted).</summary>
    public IReadOnlySet<int> InheritedSlots { get; set; } = new HashSet<int>();

    /// <summary>Editor: titles of the folders entered, for the hub caption.</summary>
    public string? LevelTitle { get; set; }

    // Interaction state

    public int? Highlighted { get; set; }
    /// <summary>Editor: the slot being edited.</summary>
    public int? Selected { get; set; }
    /// <summary>The slot just rejected (empty) and when (seconds), for the shake.</summary>
    public (int Slot, double At)? Rejected { get; set; }
    /// <summary>The slot just chosen; drives the "fire" pulse before dismissal.</summary>
    public int? Executing { get; set; }
    /// <summary>Live: drives the appear (true) and dismiss (false) animations.</summary>
    public bool IsPresented { get; set; }
    /// <summary>True while the trigger is held (marking-menu mode).</summary>
    public bool IsHolding { get; set; }
    /// <summary>Live tap mode: the pointer is over the hub, so a click there closes (or goes back).</summary>
    public bool IsHubHovered { get; set; }

    /// <summary>Live: a frosted snapshot of the screen behind the ring (Glass theme), or null.</summary>
    public ImageSource? Backdrop { get; set; }

    // Appearance

    public RingTheme Theme { get; private set; }
    public double Scale { get; private set; }
    public LabelMode LabelMode { get; private set; }
    public RingColor Accent { get; private set; }
    public bool ShowNumbers { get; private set; }
    /// <summary>0 disables animation; Windows' animation setting applies on top.</summary>
    public double AnimationSpeed { get; private set; }

    /// <summary>Where things are: the live layout fans folders out; the editor shows one level.</summary>
    public RingLayout Layout => Mode == RingMode.Live
        ? RingLayout.Live(_levels, Theme, Scale)
        : new RingLayout(Theme, Scale, Current, null, null, Fans: false);

    /// <summary>The slot whose name the hub shows: highlighted (live) or selected (editor).</summary>
    public int? FocusedSlot => Mode == RingMode.Editor ? Highlighted ?? Selected : Highlighted;

    [MemberNotNull(nameof(Accent))]
    public void Apply(AppSettings settings)
    {
        Theme = settings.Theme;
        Scale = settings.RingScale;
        LabelMode = settings.LabelMode;
        Accent = settings.Accent;
        ShowNumbers = settings.ShowSlotNumbers;
        AnimationSpeed = settings.AnimationSpeed;
    }

    /// <summary>Starts over at a root ring (a new session, or the editor showing another level).</summary>
    public void Reset(RingLevels levels)
    {
        _levels = levels;
        Highlighted = null;
        Executing = null;
        Rejected = null;
        IsHubHovered = false;
        LastLevelChange = LevelChange.Reset;
        LevelVersion++;
    }

    /// <summary>
    /// Swaps in edited content for the same level (editor): no re-animation unless the number of
    /// slots changed.
    /// </summary>
    public void Replace(RingLevels levels)
    {
        var resized = levels.Current.SlotCount != Current.SlotCount;
        _levels = levels;
        if (!resized) return;
        Highlighted = null;
        LastLevelChange = LevelChange.Reset;
        LevelVersion++;
    }

    /// <summary>The live session entered or left a folder (the levels object already changed).</summary>
    public void LevelChanged(LevelChange change)
    {
        Highlighted = null;
        LastLevelChange = change;
        LevelVersion++;
    }

    public void Reject(int slot, double now) => Rejected = (slot, now);

    public void NotifyChanged() => Changed?.Invoke();
}
