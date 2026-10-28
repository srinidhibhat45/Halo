namespace Halo.Core.Geometry;

/// <summary>A 2-D point or offset in device-independent pixels (y-down).</summary>
public readonly record struct PointD(double X, double Y)
{
    public double Length => Math.Sqrt(X * X + Y * Y);
}

/// <summary>Compass directions for arrow keys and the numeric keypad.</summary>
public enum Direction
{
    Up, Down, Left, Right, UpLeft, UpRight, DownLeft, DownRight,
}

public static class DirectionExtensions
{
    /// <summary>The direction's angle in y-down radians (0 = right, π/2 = down).</summary>
    public static double Angle(this Direction direction) => direction switch
    {
        Direction.Right => 0,
        Direction.DownRight => Math.PI / 4,
        Direction.Down => Math.PI / 2,
        Direction.DownLeft => 3 * Math.PI / 4,
        Direction.Left => Math.PI,
        Direction.UpLeft => -3 * Math.PI / 4,
        Direction.Up => -Math.PI / 2,
        _ => -Math.PI / 4,
    };

    /// <summary>Keypad digits point like a compass: 8 up, 9 up-right, 6 right … 7 up-left; else null.</summary>
    public static Direction? FromKeypadDigit(int digit) => digit switch
    {
        8 => Direction.Up,
        9 => Direction.UpRight,
        6 => Direction.Right,
        3 => Direction.DownRight,
        2 => Direction.Down,
        1 => Direction.DownLeft,
        4 => Direction.Left,
        7 => Direction.UpLeft,
        _ => null,
    };
}

/// <summary>
/// Angle maths for a ring of <see cref="SlotCount"/> equal sectors.
/// </summary>
/// <remarks>
/// Coordinates are y-down (screen convention): angle 0 points right, π/2 points down, and
/// increasing angles run clockwise on screen. Slot 0 is centred on <see cref="StartAngle"/> (top by default).
/// </remarks>
public readonly record struct RingGeometry
{
    public RingGeometry(int slotCount, double startAngle = -Math.PI / 2)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(slotCount);
        SlotCount = slotCount;
        StartAngle = startAngle;
    }

    public int SlotCount { get; }
    public double StartAngle { get; }

    /// <summary>Angular width of one sector, in radians.</summary>
    public double Step => 2 * Math.PI / SlotCount;

    /// <summary>Centre angle of slot <paramref name="i"/>, in radians (not normalised).</summary>
    public double CenterAngle(int i) => StartAngle + i * Step;

    /// <summary>Start and end angles of slot <paramref name="i"/>'s sector, shrunk by <paramref name="gap"/> radians on each side.</summary>
    public (double Start, double End) Sector(int i, double gap = 0)
    {
        var c = CenterAngle(i);
        return (c - Step / 2 + gap, c + Step / 2 - gap);
    }

    /// <summary>Offset from the ring centre to the middle of slot <paramref name="i"/> at <paramref name="radius"/>.</summary>
    public PointD Offset(int i, double radius)
    {
        var a = CenterAngle(i);
        return new PointD(Math.Cos(a) * radius, Math.Sin(a) * radius);
    }

    /// <summary>The slot whose sector contains angle <paramref name="a"/> (radians, y-down).</summary>
    public int SlotAtAngle(double a)
    {
        var relative = Normalize(a - StartAngle + Step / 2);
        return Math.Min((int)(relative / Step), SlotCount - 1);
    }

    /// <summary>
    /// The slot pointed at by an offset from the centre, or null inside the dead zone or beyond
    /// <paramref name="maxRadius"/> (pass null for an unbounded, marking-menu-style target).
    /// </summary>
    public int? SlotAt(double dx, double dy, double deadZone, double? maxRadius = null)
    {
        var r = Math.Sqrt(dx * dx + dy * dy);
        if (r < deadZone) return null;
        if (maxRadius is { } max && r > max) return null;
        return SlotAtAngle(Math.Atan2(dy, dx));
    }

    /// <summary>
    /// Like <see cref="SlotAt(double,double,double,double?)"/>, but keeps <paramref name="current"/>
    /// highlighted until the pointer is more than <paramref name="hysteresis"/> radians past its
    /// sector edge, so the highlight doesn't flicker on a boundary.
    /// </summary>
    public int? SlotAt(double dx, double dy, double deadZone, double? maxRadius, int? current, double hysteresis)
    {
        if (SlotAt(dx, dy, deadZone, maxRadius) is not { } candidate) return null;
        if (current is not { } cur || cur == candidate || cur < 0 || cur >= SlotCount) return candidate;
        var distance = AngularDistance(Math.Atan2(dy, dx), CenterAngle(cur));
        return distance <= Step / 2 + hysteresis ? cur : candidate;
    }

    /// <summary>The slot closest to a compass direction (keypad navigation).</summary>
    public int SlotToward(Direction direction) => SlotAtAngle(direction.Angle());

    /// <summary>
    /// Next slot clockwise (or counter-clockwise) from <paramref name="index"/>; from null, starts at
    /// slot 0 (or the last slot going backwards).
    /// </summary>
    public int SlotAfter(int? index, bool clockwise = true)
    {
        if (index is not { } i) return clockwise ? 0 : SlotCount - 1;
        return ((i + (clockwise ? 1 : -1)) % SlotCount + SlotCount) % SlotCount;
    }

    /// <summary>
    /// Arrow-key navigation. With nothing highlighted, jumps to the slot nearest the arrow's
    /// direction. Otherwise steps one slot (clockwise or counter-clockwise, whichever turns toward
    /// the arrow), so repeated presses walk around the ring and stop once facing that direction.
    /// </summary>
    public int SlotFrom(int? current, Direction direction)
    {
        if (current is not { } cur) return SlotToward(direction);
        var target = direction.Angle();
        var self = this;
        double Distance(int i) => AngularDistance(self.CenterAngle(i), target);
        var best = cur;
        foreach (var candidate in new[] { SlotAfter(cur, clockwise: true), SlotAfter(cur, clockwise: false) })
        {
            if (Distance(candidate) < Distance(best) - 1e-9) best = candidate;
        }
        return best;
    }

    /// <summary>Normalises an angle into 0 ..&lt; 2π.</summary>
    public static double Normalize(double a)
    {
        var twoPi = 2 * Math.PI;
        var r = a % twoPi;
        return r < 0 ? r + twoPi : r;
    }

    /// <summary>Smallest absolute difference between two angles, in 0…π.</summary>
    public static double AngularDistance(double a, double b)
    {
        var d = Normalize(a - b);
        return Math.Min(d, 2 * Math.PI - d);
    }
}

/// <summary>
/// Layout of a folder's children fanned out on an outer arc, centred on the folder's direction
/// (Logitech-style): child <c>i</c> sits at <c>CenterAngle + (i - (Count - 1) / 2) * Step</c>.
/// </summary>
/// <remarks>Angles are y-down radians. Children are picked by direction only, and only within half
/// a step beyond either end of the arc.</remarks>
public readonly record struct ArcGeometry
{
    /// <summary>22.5°: nine children span 180°.</summary>
    public const double DefaultStep = Math.PI / 8;

    public ArcGeometry(int count, double centerAngle, double step = DefaultStep)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(count);
        Count = count;
        CenterAngle = centerAngle;
        // Never wrap past a full circle.
        Step = Math.Min(step, 2 * Math.PI / count);
    }

    public int Count { get; }
    public double CenterAngle { get; }
    public double Step { get; }

    /// <summary>Centre angle of child <paramref name="i"/>.</summary>
    public double Angle(int i) => CenterAngle + (i - (Count - 1) / 2.0) * Step;

    /// <summary>Offset from the ring centre to child <paramref name="i"/> at <paramref name="radius"/>.</summary>
    public PointD Offset(int i, double radius)
    {
        var a = Angle(i);
        return new PointD(Math.Cos(a) * radius, Math.Sin(a) * radius);
    }

    /// <summary>The child whose direction contains angle <paramref name="a"/>, or null outside the arc.</summary>
    public int? SlotAtAngle(double a)
    {
        // Signed angle from the arc's centre in -π ..< π, then from the first child.
        var rel = RingGeometry.Normalize(a - CenterAngle + Math.PI) - Math.PI;
        rel += (Count - 1) / 2.0 * Step;
        var index = (int)Math.Round(rel / Step, MidpointRounding.AwayFromZero);
        if (index < 0 || index >= Count || Math.Abs(rel - index * Step) > Step / 2 + 1e-9) return null;
        return index;
    }

    /// <summary>
    /// The child pointed at by an offset, or null closer than <paramref name="minRadius"/>, beyond
    /// <paramref name="maxRadius"/> (null = unbounded) or outside the arc.
    /// </summary>
    public int? SlotAt(double dx, double dy, double minRadius, double? maxRadius = null)
    {
        var r = Math.Sqrt(dx * dx + dy * dy);
        if (r < minRadius) return null;
        if (maxRadius is { } max && r > max) return null;
        return SlotAtAngle(Math.Atan2(dy, dx));
    }

    /// <summary>The child whose direction is closest to <paramref name="direction"/> (keypad).</summary>
    public int SlotToward(Direction direction)
    {
        var best = 0;
        for (var i = 1; i < Count; i++)
        {
            if (Distance(i, direction) < Distance(best, direction)) best = i;
        }
        return best;
    }

    /// <summary>
    /// Arrow keys along the arc. With nothing highlighted, the child nearest the arrow's direction.
    /// Otherwise one step along the arc (never past its ends), whichever way turns toward the arrow,
    /// so repeated presses walk along the arc and stop once facing that direction.
    /// </summary>
    public int SlotFrom(int? current, Direction direction)
    {
        if (current is not { } cur || cur < 0 || cur >= Count) return SlotToward(direction);
        var best = cur;
        foreach (var candidate in new[] { cur + 1, cur - 1 })
        {
            if (candidate >= 0 && candidate < Count && Distance(candidate, direction) < Distance(best, direction) - 1e-9) best = candidate;
        }
        return best;
    }

    private double Distance(int child, Direction direction) => RingGeometry.AngularDistance(Angle(child), direction.Angle());
}
