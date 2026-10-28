using Halo.Core.Geometry;

namespace Halo.Core.Interaction;

/// <summary>What a pointer position is over.</summary>
public abstract record HitTarget
{
    private HitTarget() { }

    /// <summary>A slot of the current level.</summary>
    public sealed record SlotHit(int Index) : HitTarget;

    /// <summary>The centre hub (close, or back when inside a folder).</summary>
    public sealed record Hub : HitTarget;

    /// <summary>A slot of the root ring while a folder is fanned out over it.</summary>
    public sealed record RootSlot(int Index) : HitTarget;

    /// <summary>Nothing (dead zone, outside the ring, outside a folder's arc).</summary>
    public sealed record Nothing : HitTarget;

    public static HitTarget None { get; } = new Nothing();
    public static HitTarget HubHit { get; } = new Hub();
}

/// <summary>
/// Where things are on the live ring and what the pointer is over: the current level drawn as a
/// full ring, or (inside a folder) the root ring dimmed with the folder's children fanned out on
/// an outer arc centred on the folder's direction, Logitech-style. Deeper folders replace the
/// children on that arc.
/// </summary>
/// <param name="Current">The level shown.</param>
/// <param name="Root">The root ring while a folder is open, else null.</param>
/// <param name="RootAnchor">The root slot the open folder hangs from, else null.</param>
/// <param name="Fans">True for the live overlay (folders fan out); the editor shows one level at a time.</param>
public sealed record RingLayout(RingTheme Theme, double Scale, Ring Current, Ring? Root, int? RootAnchor, bool Fans)
{
    /// <summary>A layout for the ring's levels as they stand.</summary>
    public static RingLayout Live(RingLevels levels, RingTheme theme, double scale) =>
        new(theme, scale, levels.Current, levels.Depth > 0 ? levels.Root : null, levels.RootAnchor, Fans: true);

    /// <summary>True while a folder's children are fanned out over the root ring.</summary>
    public bool IsFanned => Fans && RootAnchor is not null && Root is not null;

    /// <summary>Metrics for the ring on screen (the root ring while a folder is fanned out over it).</summary>
    public RingMetrics Metrics => new(Theme, Scale, (IsFanned ? Root! : Current).SlotCount);

    /// <summary>Geometry of the shown level drawn as a full ring.</summary>
    public RingGeometry Geometry => new(Current.SlotCount);

    /// <summary>Layout of the fanned-out children of the current level, if fanned.</summary>
    public ArcGeometry? ChildArc
    {
        get
        {
            if (!IsFanned) return null;
            var rootGeometry = new RingGeometry(Root!.SlotCount);
            return new ArcGeometry(Current.SlotCount, rootGeometry.CenterAngle(RootAnchor!.Value), Metrics.ChildStep);
        }
    }

    /// <summary>
    /// Classifies a pointer offset from the ring centre (y-down).
    /// </summary>
    /// <param name="holding">The trigger is held (marking-menu mode): small dead zone, unbounded reach, the hub is not a target.</param>
    /// <param name="current">The highlighted slot, for hysteresis.</param>
    public HitTarget HitTest(double dx, double dy, bool holding, int? current)
    {
        var m = Metrics;
        var r = Math.Sqrt(dx * dx + dy * dy);
        if (!holding && r <= m.HubRadius) return HitTarget.HubHit;

        if (ChildArc is { } arc)
        {
            // Children live beyond the midpoint between the root ring and the folder ring.
            var minRadius = (m.SlotCenterRadius + m.FolderRadius) / 2;
            if (r < minRadius)
            {
                // Over the dimmed root ring: hovering another root slot switches to it (like a menu
                // bar), in both modes. The centre stays inert.
                var inner = holding ? m.HoldDeadZone : m.HubRadius;
                if (r <= inner) return HitTarget.None;
                var rootIndex = new RingGeometry(Root!.SlotCount).SlotAt(dx, dy, inner, minRadius);
                return rootIndex is { } i ? new HitTarget.RootSlot(i) : HitTarget.None;
            }
            double? maxRadius = holding ? null : m.FolderRadius + m.SlotSize / 2 + 60;
            return arc.SlotAt(dx, dy, minRadius, maxRadius) is { } child ? new HitTarget.SlotHit(child) : HitTarget.None;
        }

        var deadZone = holding ? m.HoldDeadZone : m.TapDeadZone;
        double? max = holding ? null : m.MaxHitRadius;
        return Geometry.SlotAt(dx, dy, deadZone, max, current, m.Hysteresis) is { } slot
            ? new HitTarget.SlotHit(slot)
            : HitTarget.None;
    }

    /// <summary>Where slot <paramref name="index"/> of the shown level is drawn, as an offset from the
    /// ring centre: on the ring, or on the folder arc when fanned.</summary>
    public PointD SlotOffset(int index)
    {
        var m = Metrics;
        return ChildArc is { } arc ? arc.Offset(index, m.FolderRadius) : Geometry.Offset(index, m.SlotCenterRadius);
    }

    /// <summary>Arrow keys: on the ring, or along a fanned-out folder's arc.</summary>
    public int SlotFrom(int? current, Direction direction) =>
        ChildArc is { } arc ? arc.SlotFrom(current, direction) : Geometry.SlotFrom(current, direction);

    /// <summary>Keypad directions: the slot (or fanned-out child) nearest the direction.</summary>
    public int SlotToward(Direction direction) =>
        ChildArc is { } arc ? arc.SlotToward(direction) : Geometry.SlotToward(direction);

    /// <summary>Tab / Shift+Tab: the next slot around the ring (or along the arc) that holds something.</summary>
    public int CycledSlot(int? current, bool clockwise)
    {
        var geometry = Geometry;
        var candidate = geometry.SlotAfter(current, clockwise);
        for (var i = 0; i < geometry.SlotCount; i++)
        {
            if (!Current[candidate].IsEmpty) return candidate;
            candidate = geometry.SlotAfter(candidate, clockwise);
        }
        return geometry.SlotAfter(current, clockwise);
    }
}
