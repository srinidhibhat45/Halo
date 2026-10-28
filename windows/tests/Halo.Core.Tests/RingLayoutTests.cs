using Halo.Core.Catalog;
using Halo.Core.Geometry;
using Halo.Core.Interaction;

namespace Halo.Core.Tests;

public class RingLayoutTests
{
    private static RingLevels Levels() => new(DefaultRings.Global());

    private static (double X, double Y) Polar(double degrees, double radius)
    {
        var a = degrees * Math.PI / 180;
        return (Math.Cos(a) * radius, Math.Sin(a) * radius);
    }

    [Fact(DisplayName = "Classic metrics match Logitech's ring at Medium")]
    public void ClassicMetrics()
    {
        var m = new RingMetrics(RingTheme.Classic, 1, 8);
        Assert.Equal(46, m.SlotSize);
        Assert.Equal(82.5, m.SlotCenterRadius);
        Assert.Equal(15.5, m.HubRadius);
        Assert.Equal(165, m.FolderRadius);
        Assert.True(new RingMetrics(RingTheme.Classic, 1, 12).SlotCenterRadius > 82.5);   // grows so bubbles don't touch
        Assert.Equal(2 * m.SlotCenterRadius, new RingMetrics(RingTheme.Classic, 2, 8).SlotCenterRadius, 6);
    }

    [Fact(DisplayName = "In tap mode the hub is a target and the ring is bounded")]
    public void TapMode()
    {
        var layout = RingLayout.Live(Levels(), RingTheme.Classic, 1);
        Assert.Equal(HitTarget.HubHit, layout.HitTest(3, 4, holding: false, current: null));
        Assert.Equal(new HitTarget.SlotHit(2), layout.HitTest(80, 0, false, null));
        Assert.Equal(HitTarget.None, layout.HitTest(0, -500, false, null));
    }

    [Fact(DisplayName = "While holding the hub is inert and reach is unbounded")]
    public void Holding()
    {
        var layout = RingLayout.Live(Levels(), RingTheme.Classic, 1);
        Assert.Equal(HitTarget.None, layout.HitTest(3, 4, holding: true, current: null));
        Assert.Equal(new HitTarget.SlotHit(0), layout.HitTest(0, -900, true, null));
        Assert.Equal(new HitTarget.SlotHit(0), layout.HitTest(0, -17, true, null));
    }

    [Fact(DisplayName = "A fanned folder: children on the outer arc, root slots switch, centre inert")]
    public void Fanned()
    {
        var levels = Levels();
        Assert.NotNull(levels.EnterFolder(5));   // "Windows" folder at 135° (bottom-left, y-down), 6 children
        var layout = RingLayout.Live(levels, RingTheme.Classic, 1);
        Assert.True(layout.IsFanned);
        var arc = layout.ChildArc!.Value;
        Assert.Equal(6, arc.Count);
        Assert.Equal(new RingGeometry(8).CenterAngle(5), arc.CenterAngle, 9);

        // Child 2 sits on the folder radius.
        var child = layout.SlotOffset(2);
        Assert.Equal(layout.Metrics.FolderRadius, child.Length, 6);
        Assert.Equal(new HitTarget.SlotHit(2), layout.HitTest(child.X, child.Y, false, null));

        // Over the dimmed root ring: the folder's own slot, another root slot, the centre.
        var (fx, fy) = Polar(135, 82.5);
        Assert.Equal(new HitTarget.RootSlot(5), layout.HitTest(fx, fy, false, null));
        var (tx, ty) = Polar(-90, 82.5);
        Assert.Equal(new HitTarget.RootSlot(0), layout.HitTest(tx, ty, false, null));
        Assert.Equal(HitTarget.None, layout.HitTest(0, 10, holding: true, current: null));

        // Outside the arc (opposite side, beyond the root ring) is nothing.
        var (ox, oy) = Polar(-45, 200);
        Assert.Equal(HitTarget.None, layout.HitTest(ox, oy, false, null));
    }

    [Fact(DisplayName = "Arrow keys and Tab follow the arc when fanned, the ring otherwise")]
    public void Navigation()
    {
        var levels = Levels();
        var root = RingLayout.Live(levels, RingTheme.Classic, 1);
        Assert.Equal(2, root.SlotFrom(null, Direction.Right));
        Assert.Equal(4, root.CycledSlot(3, clockwise: true));

        levels.EnterFolder(5);
        var fanned = RingLayout.Live(levels, RingTheme.Classic, 1);
        var fromNothing = fanned.SlotFrom(null, Direction.DownLeft);
        Assert.InRange(fromNothing, 2, 3);
        Assert.Equal(0, fanned.CycledSlot(null, clockwise: true));
    }

    [Fact(DisplayName = "The editor never fans folders")]
    public void EditorLayout()
    {
        var folder = DefaultRings.Windows();
        var layout = new RingLayout(RingTheme.Glass, 1, folder, DefaultRings.Global(), 5, Fans: false);
        Assert.False(layout.IsFanned);
        Assert.Null(layout.ChildArc);
        Assert.Equal(layout.Metrics.SlotCenterRadius, layout.SlotOffset(0).Length, 6);
    }

    [Fact(DisplayName = "Closing gaps shows filled slots only and maps edits back to configured positions")]
    public void ClosingGaps()
    {
        var folder = new Ring(6).WithSlot(2, new Slot(new MediaAction(MediaCommand.Mute))).WithSlot(5, new Slot(new EditAction(EditCommand.Copy)));
        var root = new Ring(8)
            .WithSlot(1, new Slot(new MediaAction(MediaCommand.PlayPause)))
            .WithSlot(3, new Slot(new FolderAction(folder), "Media"))
            .WithSlot(6, new Slot(new SystemAction(SystemCommand.LockScreen)));
        var levels = new RingLevels(root, closesGaps: true);
        Assert.Equal(3, levels.Root.SlotCount);
        Assert.Equal((new Editing.RingAddress(Editing.RingTarget.Everywhere), (int?)6), levels.EditDestination(2));
        Assert.Equal(2, levels.EnterFolder(1)?.SlotCount);
        Assert.Equal((new Editing.RingAddress(Editing.RingTarget.Everywhere, [3]), (int?)5), levels.EditDestination(1));

        var layout = RingLayout.Live(levels, RingTheme.Classic, 1);
        Assert.Equal(2, layout.ChildArc?.Count);
        Assert.Equal(new RingGeometry(3).CenterAngle(1), layout.ChildArc!.Value.CenterAngle, 9);

        var open = new RingLevels(root, closesGaps: false);
        Assert.Equal(8, open.Root.SlotCount);
        Assert.Equal(1, open.EditDestination(1).Slot);
    }

    [Fact(DisplayName = "Inherited slots of an app ring are edited in the global ring")]
    public void InheritedEditDestination()
    {
        var profileId = Guid.NewGuid();
        var own = new Ring(8).WithSlot(0, new Slot(new EditAction(EditCommand.Copy)));
        var resolved = own.WithSlot(1, new Slot(new MediaAction(MediaCommand.Mute)));
        var levels = new RingLevels(resolved, closesGaps: false, new Editing.RingTarget.App(profileId), own);
        Assert.Equal(new Editing.RingTarget.App(profileId), levels.EditDestination(0).Address.Target);
        Assert.Equal(Editing.RingTarget.Everywhere, levels.EditDestination(1).Address.Target);
    }

    [Fact(DisplayName = "Levels enter and leave folders and report kinds")]
    public void LevelsEnterAndLeave()
    {
        var levels = Levels();
        Assert.Null(levels.EnterFolder(0));   // not a folder
        Assert.NotNull(levels.EnterFolder(3));
        Assert.Equal(["AI"], levels.Breadcrumb);
        Assert.Equal([3], levels.EditDestination(null).Address.Path);
        Assert.Equal(3, levels.RootAnchor);
        var back = levels.ExitFolder();
        Assert.Equal(3, back?.FolderSlot);
        Assert.Equal(0, levels.Depth);
        Assert.Null(levels.ExitFolder());
        Assert.Equal(SlotKind.Folder, RingLevels.KindsOf(DefaultRings.Global())[5]);
        Assert.Equal(SlotKind.Empty, RingLevels.KindsOf(new Ring(4))[0]);
        var big = new Ring([new Slot(new FolderAction(new Ring(12)))]);
        Assert.Equal(12, RingLevels.LargestSlotCount(big));
    }
}
