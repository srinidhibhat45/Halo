using Halo.Core.Interaction;
using static Halo.Core.Tests.Effects;

namespace Halo.Core.Tests;

/// <summary>Shorthand for expected effect lists.</summary>
internal static class Effects
{
    public static readonly RingEffect Show = new RingEffect.Show();
    public static readonly RingEffect Dismiss = new RingEffect.Dismiss();
    public static readonly RingEffect ExitFolder = new RingEffect.ExitFolder();
    public static RingEffect Highlight(int? slot) => new RingEffect.Highlight(slot);
    public static RingEffect Execute(int slot) => new RingEffect.Execute(slot);
    public static RingEffect EnterFolder(int slot) => new RingEffect.EnterFolder(slot);
    public static RingEffect Reject(int slot) => new RingEffect.Reject(slot);
    public static RingEffect[] E(params RingEffect[] effects) => effects;
}

public class RingInteractionTests
{
    /// <summary>8 slots: 0-5 actions, 6 folder, 7 empty.</summary>
    private static readonly SlotKind[] Level =
        [SlotKind.Action, SlotKind.Action, SlotKind.Action, SlotKind.Action, SlotKind.Action, SlotKind.Action, SlotKind.Folder, SlotKind.Empty];

    private static readonly SlotKind[] FolderLevel = [SlotKind.Action, SlotKind.Action, SlotKind.Action, SlotKind.Action];

    private static RingInteraction Opened(SelectionMode mode = SelectionMode.Auto)
    {
        var r = new RingInteraction(mode, holdThreshold: 0.3);
        Assert.Equal(E(Show), r.TriggerDown(0));
        r.SetLevel(Level);
        return r;
    }

    [Fact(DisplayName = "Quick tap keeps the ring open")]
    public void TapSticks()
    {
        var r = Opened();
        Assert.Empty(r.TriggerUp(0.1));
        Assert.IsType<RingPhase.Open>(r.Phase);
    }

    [Fact(DisplayName = "Hold, point, release runs the slot")]
    public void HoldRelease()
    {
        var r = Opened();
        Assert.Equal(E(Highlight(2)), r.PointerMoved(2));
        Assert.Equal(E(Execute(2)), r.TriggerUp(0.6));
        Assert.IsType<RingPhase.Closed>(r.Phase);
    }

    [Fact(DisplayName = "A fast flick then release still runs (mark-ahead)")]
    public void Flick()
    {
        var r = Opened();
        r.PointerMoved(4);
        Assert.Equal(E(Execute(4)), r.TriggerUp(0.12));
    }

    [Fact(DisplayName = "Holding, then releasing in the centre cancels")]
    public void HoldCancel()
    {
        var r = Opened();
        Assert.Equal(E(Dismiss), r.TriggerUp(0.8));
        Assert.False(r.IsOpen);
    }

    [Fact(DisplayName = "Releasing over an empty slot cancels")]
    public void ReleaseOnEmpty()
    {
        var r = Opened();
        r.PointerMoved(7);
        Assert.Equal(E(Dismiss), r.TriggerUp(0.8));
    }

    [Fact(DisplayName = "Clicking an empty slot rejects and stays open")]
    public void ClickEmpty()
    {
        var r = Opened();
        r.TriggerUp(0.1);
        Assert.Equal(E(Reject(7)), r.Click(7));
        Assert.IsType<RingPhase.Open>(r.Phase);
    }

    [Fact(DisplayName = "Clicking an empty slot while holding rejects and stops holding")]
    public void ClickEmptyWhileHolding()
    {
        var r = Opened();
        Assert.Equal(E(Reject(7)), r.Click(7));
        Assert.IsType<RingPhase.Open>(r.Phase);
    }

    [Fact(DisplayName = "Second press runs the highlighted slot, or closes")]
    public void SecondPress()
    {
        var r = Opened();
        r.TriggerUp(0.1);
        r.PointerMoved(1);
        Assert.Equal(E(Execute(1)), r.TriggerDown(1.0));
        Assert.Empty(r.TriggerUp(1.1));

        var s = Opened();
        s.TriggerUp(0.1);
        Assert.Equal(E(Dismiss), s.TriggerDown(1.0));
    }

    [Fact(DisplayName = "Key auto-repeat is ignored while holding")]
    public void AutoRepeat()
    {
        var r = Opened();
        Assert.Empty(r.TriggerDown(0.05));
        Assert.Equal(new RingPhase.Holding(0), r.Phase);
    }

    [Fact(DisplayName = "Folders: enter on release, back with Escape, close at root")]
    public void Folders()
    {
        var r = Opened();
        r.PointerMoved(6);
        Assert.Equal(E(EnterFolder(6), Highlight(null)), r.TriggerUp(0.7));
        Assert.IsType<RingPhase.Open>(r.Phase);
        Assert.Equal(1, r.Depth);
        r.SetLevel(FolderLevel);
        Assert.Equal(E(ExitFolder, Highlight(null)), r.Escape());
        Assert.Equal(0, r.Depth);
        r.SetLevel(Level);
        Assert.Equal(E(Dismiss), r.Escape());
    }

    [Fact(DisplayName = "Clicking the hub inside a folder goes back; at the root it closes")]
    public void Hub()
    {
        var r = Opened();
        r.TriggerUp(0.1);
        r.Click(6);
        r.SetLevel(FolderLevel);
        Assert.Equal(E(ExitFolder, Highlight(null)), r.Click(null, inHub: true));
        r.SetLevel(Level);
        Assert.Equal(E(Dismiss), r.Click(null, inHub: true));
    }

    [Fact(DisplayName = "Number keys pick slots; 0 is the tenth")]
    public void Numbers()
    {
        var r = Opened();
        r.TriggerUp(0.1);
        Assert.Equal(E(Execute(2)), r.Number(3));

        var s = Opened();
        Assert.Empty(s.Number(0));   // only 8 slots
        Assert.Empty(s.Number(9));
    }

    [Fact(DisplayName = "Return runs the highlight; nothing highlighted does nothing")]
    public void Confirm()
    {
        var r = Opened();
        r.TriggerUp(0.1);
        Assert.Empty(r.Confirm());
        r.SetHighlight(5);
        Assert.Equal(E(Execute(5)), r.Confirm());
    }

    [Fact(DisplayName = "Tap-then-click never runs on release")]
    public void TapMode()
    {
        var r = Opened(SelectionMode.TapThenClick);
        r.PointerMoved(2);
        Assert.Empty(r.TriggerUp(1.0));
        Assert.IsType<RingPhase.Open>(r.Phase);
        Assert.Equal(E(Execute(2)), r.Click(2));
    }

    [Fact(DisplayName = "Hold-and-release cancels a tap with nothing highlighted")]
    public void HoldMode()
    {
        var r = Opened(SelectionMode.HoldAndRelease);
        Assert.Equal(E(Dismiss), r.TriggerUp(0.05));
    }

    [Fact(DisplayName = "Hold-and-release runs the highlight even on a quick release")]
    public void HoldModeQuickRelease()
    {
        var r = Opened(SelectionMode.HoldAndRelease);
        r.PointerMoved(3);
        Assert.Equal(E(Execute(3)), r.TriggerUp(0.05));
    }

    [Fact(DisplayName = "Pointer moves only report changes and ignore out-of-range slots")]
    public void Pointer()
    {
        var r = Opened();
        Assert.Equal(E(Highlight(3)), r.PointerMoved(3));
        Assert.Empty(r.PointerMoved(3));
        Assert.Equal(E(Highlight(null)), r.PointerMoved(42));
    }

    [Fact(DisplayName = "Dwelling on a folder while holding opens it and keeps holding")]
    public void DwellOpensFolder()
    {
        var r = Opened();
        r.PointerMoved(6);
        Assert.Equal(E(EnterFolder(6), Highlight(null)), r.Dwell(6));
        Assert.Equal(1, r.Depth);
        r.SetLevel(FolderLevel);
        r.PointerMoved(2);
        Assert.Equal(E(Execute(2)), r.TriggerUp(1.2));
    }

    [Fact(DisplayName = "Dwell does nothing on actions or off the highlight")]
    public void DwellIgnored()
    {
        var r = Opened();
        r.PointerMoved(1);
        Assert.Empty(r.Dwell(1));
        Assert.Empty(r.Dwell(6));
    }

    [Fact(DisplayName = "Hovering a folder in tap mode opens it and stays in tap mode")]
    public void DwellInTapMode()
    {
        var r = Opened();
        r.TriggerUp(0.1);   // now sticky
        r.PointerMoved(6);
        Assert.Equal(E(EnterFolder(6), Highlight(null)), r.Dwell(6));
        Assert.IsType<RingPhase.Open>(r.Phase);
        Assert.Equal(1, r.Depth);
    }

    [Fact(DisplayName = "Backing out of a folder while holding keeps holding, so release still runs")]
    public void BackWhileHolding()
    {
        var r = Opened();
        r.PointerMoved(6);
        r.Dwell(6);
        r.SetLevel(FolderLevel);
        Assert.Equal(E(ExitFolder, Highlight(null)), r.Back());
        Assert.Equal(new RingPhase.Holding(0), r.Phase);
        r.SetLevel(Level);
        r.PointerMoved(2);
        Assert.Equal(E(Execute(2)), r.TriggerUp(1.0));
    }

    [Fact(DisplayName = "Back does nothing at the root")]
    public void BackAtRoot()
    {
        var r = Opened();
        Assert.Empty(r.Back());
        Assert.True(r.IsOpen);
    }

    [Fact(DisplayName = "Clicking outside closes")]
    public void Outside()
    {
        var r = Opened();
        r.TriggerUp(0.1);
        Assert.Equal(E(Dismiss), r.Click(null));
    }

    [Fact(DisplayName = "Cancel closes an open ring and does nothing when closed")]
    public void Cancel()
    {
        var r = Opened();
        Assert.Equal(E(Dismiss), r.Cancel());
        Assert.Empty(r.Cancel());
        Assert.Empty(r.PointerMoved(1));
    }

    [Fact(DisplayName = "A shorter level drops a highlight that no longer exists")]
    public void SetLevelDropsHighlight()
    {
        var r = Opened();
        r.PointerMoved(7);
        r.SetLevel(FolderLevel);
        Assert.Null(r.Highlighted);
    }
}
