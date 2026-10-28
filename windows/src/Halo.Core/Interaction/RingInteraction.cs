namespace Halo.Core.Interaction;

/// <summary>What occupies each slot of the ring level currently shown.</summary>
public enum SlotKind
{
    Empty, Action, Folder,
}

/// <summary>Where the ring's input state machine is.</summary>
public abstract record RingPhase
{
    private RingPhase() { }

    public sealed record Closed : RingPhase;

    /// <summary>The trigger is down; the ring opened at <paramref name="Since"/> (seconds, any monotonic clock).</summary>
    public sealed record Holding(double Since) : RingPhase;

    /// <summary>The ring stays open until something is chosen or it is dismissed.</summary>
    public sealed record Open : RingPhase;
}

/// <summary>What the overlay must do in response to input.</summary>
public abstract record RingEffect
{
    private RingEffect() { }

    /// <summary>Show the ring (at the pointer) with the root level.</summary>
    public sealed record Show : RingEffect;

    /// <summary>Dismiss without running anything.</summary>
    public sealed record Dismiss : RingEffect;

    public sealed record Highlight(int? Slot) : RingEffect;

    /// <summary>Run the slot's action at the current level, then dismiss.</summary>
    public sealed record Execute(int Slot) : RingEffect;

    /// <summary>Replace the current level with the folder at this slot.</summary>
    public sealed record EnterFolder(int Slot) : RingEffect;

    /// <summary>Return to the parent level.</summary>
    public sealed record ExitFolder : RingEffect;

    /// <summary>The slot can't be chosen (it is empty): give "nope" feedback, stay open.</summary>
    public sealed record Reject(int Slot) : RingEffect;
}

/// <summary>
/// The ring's input state machine, free of UI so it can be tested.
/// </summary>
/// <remarks>
/// The overlay feeds it trigger presses and releases, pointer moves (already mapped to a slot
/// index), clicks and keys, and applies the returned effects (show, highlight, run, enter
/// folder…). It supports both ways of using the trigger:
/// <list type="bullet">
/// <item>tap: the ring stays open; click a slot, press 1–9, or press the trigger again on a slot;</item>
/// <item>hold: point at a slot and release to run it; release in the centre to cancel.</item>
/// </list>
/// </remarks>
public sealed class RingInteraction
{
    private static readonly RingEffect[] None = [];
    private IReadOnlyList<SlotKind> _level = [];

    public RingInteraction(SelectionMode mode = SelectionMode.Auto, double holdThreshold = 0.28)
    {
        Mode = mode;
        HoldThreshold = holdThreshold;
    }

    public SelectionMode Mode { get; set; }
    /// <summary>Seconds the trigger must be held for a release to count as "hold" in <see cref="SelectionMode.Auto"/>.</summary>
    public double HoldThreshold { get; set; }

    public RingPhase Phase { get; private set; } = new RingPhase.Closed();
    public int? Highlighted { get; private set; }
    /// <summary>Folder depth of the level shown (0 = root).</summary>
    public int Depth { get; private set; }

    public bool IsOpen => Phase is not RingPhase.Closed;
    public bool IsHolding => Phase is RingPhase.Holding;

    /// <summary>
    /// Tells the machine what the shown level contains. Call after <see cref="RingEffect.Show"/>,
    /// <see cref="RingEffect.EnterFolder"/> and <see cref="RingEffect.ExitFolder"/>.
    /// </summary>
    public void SetLevel(IReadOnlyList<SlotKind> kinds)
    {
        _level = kinds;
        if (Highlighted is { } h && h >= kinds.Count) Highlighted = null;
    }

    // Trigger

    public IReadOnlyList<RingEffect> TriggerDown(double time)
    {
        switch (Phase)
        {
            case RingPhase.Closed:
                Phase = new RingPhase.Holding(time);
                Highlighted = null;
                Depth = 0;
                return [new RingEffect.Show()];
            case RingPhase.Holding:
                // Key auto-repeat or a duplicate press: ignore.
                return None;
            default:
                // Second press: run what is highlighted, or toggle the ring closed.
                return Highlighted is { } h ? Activate(h) : Close();
        }
    }

    public IReadOnlyList<RingEffect> TriggerUp(double time)
    {
        if (Phase is not RingPhase.Holding holding) return None;
        var heldLongEnough = time - holding.Since >= HoldThreshold;
        switch (Mode)
        {
            case SelectionMode.TapThenClick:
                Phase = new RingPhase.Open();
                return None;
            case SelectionMode.HoldAndRelease:
                return Highlighted is { } h ? ActivateOnRelease(h) : Close();
            default:
                if (Highlighted is { } highlighted) return ActivateOnRelease(highlighted);
                if (heldLongEnough) return Close();
                Phase = new RingPhase.Open();
                return None;
        }
    }

    // Pointer

    /// <summary>The pointer now points at <paramref name="slot"/> (null = centre or outside).</summary>
    public IReadOnlyList<RingEffect> PointerMoved(int? slot)
    {
        if (!IsOpen) return None;
        var s = slot is { } i && i >= 0 && i < _level.Count ? slot : null;
        if (s == Highlighted) return None;
        Highlighted = s;
        return [new RingEffect.Highlight(s)];
    }

    /// <summary>A click on a slot, on the hub (<paramref name="slot"/> null, <paramref name="inHub"/> true) or outside the ring.</summary>
    public IReadOnlyList<RingEffect> Click(int? slot, bool inHub = false)
    {
        if (!IsOpen) return None;
        if (slot is { } index) return Activate(index);
        if (inHub && Depth > 0) return ExitFolder();
        return Close();
    }

    // Keyboard

    public IReadOnlyList<RingEffect> Escape()
    {
        if (!IsOpen) return None;
        return Depth > 0 ? ExitFolder() : Close();
    }

    /// <summary>Backspace/Delete: back out of a folder; does nothing at the root.</summary>
    public IReadOnlyList<RingEffect> Back() => IsOpen && Depth > 0 ? ExitFolder() : None;

    /// <summary>Number keys: 1 is slot 0 … 9 is slot 8, 0 is slot 9.</summary>
    public IReadOnlyList<RingEffect> Number(int n)
    {
        if (!IsOpen) return None;
        var index = n == 0 ? 9 : n - 1;
        return index >= 0 && index < _level.Count ? Activate(index) : None;
    }

    /// <summary>
    /// The pointer rested on <paramref name="slot"/> briefly (the caller times the dwell). Hovering a
    /// folder opens it without a click, like a submenu: while holding, nested actions are reached in
    /// one stroke; in tap mode the folder simply opens.
    /// </summary>
    public IReadOnlyList<RingEffect> Dwell(int slot)
    {
        if (!IsOpen || Highlighted != slot || slot < 0 || slot >= _level.Count || _level[slot] != SlotKind.Folder) return None;
        Depth += 1;
        Highlighted = null;
        // Keep the phase: while holding, releasing over a slot of the folder runs it.
        return [new RingEffect.EnterFolder(slot), new RingEffect.Highlight(null)];
    }

    /// <summary>Moves the highlight (arrow keys, Tab), computed by the caller from the ring's geometry.</summary>
    public IReadOnlyList<RingEffect> SetHighlight(int? slot) => PointerMoved(slot);

    /// <summary>Enter/Space: run the highlighted slot.</summary>
    public IReadOnlyList<RingEffect> Confirm() => IsOpen && Highlighted is { } h ? Activate(h) : None;

    /// <summary>Dismiss from outside (app switch, display change, session lock…).</summary>
    public IReadOnlyList<RingEffect> Cancel() => IsOpen ? Close() : None;

    // Internals

    private IReadOnlyList<RingEffect> ActivateOnRelease(int index)
    {
        // Releasing over an empty slot cancels rather than leaving a ring open that the user was
        // clearly done with.
        if (index >= 0 && index < _level.Count && _level[index] == SlotKind.Empty) return Close();
        return Activate(index);
    }

    private IReadOnlyList<RingEffect> Activate(int index)
    {
        if (index < 0 || index >= _level.Count) return None;
        switch (_level[index])
        {
            case SlotKind.Empty:
                if (Phase is RingPhase.Holding) Phase = new RingPhase.Open();
                return [new RingEffect.Reject(index)];
            case SlotKind.Folder:
                Depth += 1;
                Phase = new RingPhase.Open();
                Highlighted = null;
                return [new RingEffect.EnterFolder(index), new RingEffect.Highlight(null)];
            default:
                Reset();
                return [new RingEffect.Execute(index)];
        }
    }

    private IReadOnlyList<RingEffect> ExitFolder()
    {
        Depth -= 1;
        Highlighted = null;
        // Going back while the trigger is held keeps holding, so a hover-switch to another root
        // slot can still be released to run it.
        if (Phase is not RingPhase.Holding) Phase = new RingPhase.Open();
        return [new RingEffect.ExitFolder(), new RingEffect.Highlight(null)];
    }

    private IReadOnlyList<RingEffect> Close()
    {
        Reset();
        return [new RingEffect.Dismiss()];
    }

    private void Reset()
    {
        Phase = new RingPhase.Closed();
        Highlighted = null;
        Depth = 0;
        _level = [];
    }
}
