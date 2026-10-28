using Halo.Core.Geometry;

namespace Halo.Core.Tests;

public class RingGeometryTests
{
    private static readonly RingGeometry Eight = new(8);

    private static double Rad(double degrees) => degrees * Math.PI / 180;

    [Fact(DisplayName = "Slot 0 is at the top and slots run clockwise")]
    public void ClockwiseFromTop()
    {
        Assert.Equal(0, Eight.SlotAt(0, -100, 20));
        Assert.Equal(1, Eight.SlotAt(70, -70, 20));
        Assert.Equal(2, Eight.SlotAt(100, 0, 20));
        Assert.Equal(3, Eight.SlotAt(70, 70, 20));
        Assert.Equal(4, Eight.SlotAt(0, 100, 20));
        Assert.Equal(5, Eight.SlotAt(-70, 70, 20));
        Assert.Equal(6, Eight.SlotAt(-100, 0, 20));
        Assert.Equal(7, Eight.SlotAt(-70, -70, 20));
    }

    [Fact(DisplayName = "Sector boundaries split evenly around each slot centre")]
    public void Boundaries()
    {
        // Slot 0 spans -112.5° … -67.5°.
        Assert.Equal(0, Eight.SlotAtAngle(Rad(-90 + 22.4)));
        Assert.Equal(1, Eight.SlotAtAngle(Rad(-90 + 22.6)));
        Assert.Equal(0, Eight.SlotAtAngle(Rad(-90 - 22.4)));
        Assert.Equal(7, Eight.SlotAtAngle(Rad(-90 - 22.6)));
    }

    [Fact(DisplayName = "Dead zone and max radius return null")]
    public void DeadZoneAndMaxRadius()
    {
        Assert.Null(Eight.SlotAt(5, -5, 20));
        Assert.Null(Eight.SlotAt(0, -500, 20, 300));
        Assert.Equal(0, Eight.SlotAt(0, -500, 20, null));
    }

    [Theory(DisplayName = "Works for every supported slot count")]
    [InlineData(4)] [InlineData(5)] [InlineData(6)] [InlineData(7)] [InlineData(8)]
    [InlineData(9)] [InlineData(10)] [InlineData(11)] [InlineData(12)]
    public void EveryCount(int n)
    {
        var g = new RingGeometry(n);
        for (var i = 0; i < n; i++)
        {
            var p = g.Offset(i, 100);
            Assert.Equal(i, g.SlotAt(p.X, p.Y, 10));
        }
    }

    [Fact(DisplayName = "Arrow keys jump, then walk toward the arrow")]
    public void Arrows()
    {
        Assert.Equal(2, Eight.SlotFrom(null, Direction.Right));
        Assert.Equal(6, Eight.SlotFrom(null, Direction.Left));
        Assert.Equal(1, Eight.SlotFrom(0, Direction.Right));
        Assert.Equal(2, Eight.SlotFrom(1, Direction.Right));
        Assert.Equal(2, Eight.SlotFrom(2, Direction.Right));
        Assert.Equal(1, Eight.SlotFrom(0, Direction.Down));   // opposite: tie breaks clockwise
    }

    [Fact(DisplayName = "Hysteresis holds the current slot just past its edge")]
    public void Hysteresis()
    {
        var five = Rad(5);
        // 24° clockwise from north: past slot 0's edge (22.5°) but inside the 5° hysteresis.
        var a = Rad(-90 + 24);
        var (dx, dy) = (Math.Cos(a) * 100, Math.Sin(a) * 100);
        Assert.Equal(1, Eight.SlotAt(dx, dy, 16));
        Assert.Equal(0, Eight.SlotAt(dx, dy, 16, null, 0, five));
        // 30°: beyond the hysteresis band.
        var b = Rad(-90 + 30);
        Assert.Equal(1, Eight.SlotAt(Math.Cos(b) * 100, Math.Sin(b) * 100, 16, null, 0, five));
        // Dead zone still wins.
        Assert.Null(Eight.SlotAt(1, 1, 16, null, 0, five));
    }

    [Fact(DisplayName = "Tab cycles both ways")]
    public void Cycling()
    {
        Assert.Equal(0, Eight.SlotAfter(null));
        Assert.Equal(0, Eight.SlotAfter(7));
        Assert.Equal(7, Eight.SlotAfter(0, clockwise: false));
        Assert.Equal(7, Eight.SlotAfter(null, clockwise: false));
    }

    [Fact(DisplayName = "Keypad digits map to compass directions")]
    public void Keypad()
    {
        Assert.Equal(Direction.Up, DirectionExtensions.FromKeypadDigit(8));
        Assert.Equal(Direction.DownLeft, DirectionExtensions.FromKeypadDigit(1));
        Assert.Null(DirectionExtensions.FromKeypadDigit(5));
        Assert.Equal(1, Eight.SlotToward(DirectionExtensions.FromKeypadDigit(9)!.Value));
    }

    [Fact(DisplayName = "A ring needs at least one slot")]
    public void RejectsZero() => Assert.Throws<ArgumentOutOfRangeException>(() => new RingGeometry(0));
}

public class ArcGeometryTests
{
    [Fact(DisplayName = "Children fan out centred on the folder's direction")]
    public void Centred()
    {
        var right = new ArcGeometry(3, 0);
        Assert.True(Math.Abs(right.Angle(1)) < 1e-9);
        Assert.True(Math.Abs(right.Angle(0) + Math.PI / 8) < 1e-9);
        Assert.Equal(1, right.SlotAt(100, 0, 50));
        Assert.Equal(0, right.SlotAt(100, -40, 50));   // up-right
        Assert.Equal(2, right.SlotAt(100, 40, 50));
    }

    [Fact(DisplayName = "Outside the arc, inside the min radius, or beyond max picks nothing")]
    public void Outside()
    {
        var up = new ArcGeometry(3, -Math.PI / 2);
        Assert.Null(up.SlotAt(0, 100, 50));      // opposite side
        Assert.Null(up.SlotAt(0, -30, 50));
        Assert.Null(up.SlotAt(0, -400, 50, 300));
        Assert.Equal(1, up.SlotAt(0, -100, 50));
    }

    [Fact(DisplayName = "Arcs that cross the ±π seam still resolve")]
    public void Seam()
    {
        var left = new ArcGeometry(4, Math.PI);
        for (var i = 0; i < 4; i++)
        {
            var p = left.Offset(i, 100);
            Assert.Equal(i, left.SlotAt(p.X, p.Y, 10));
        }
    }

    [Fact(DisplayName = "Many children never wrap past a full circle")]
    public void ClampStep()
    {
        var many = new ArcGeometry(20, 0);
        Assert.True(many.Step <= 2 * Math.PI / 20 + 1e-12);
    }

    [Fact(DisplayName = "Arrow keys walk along the arc and stop at its ends")]
    public void ArcArrows()
    {
        var right = new ArcGeometry(5, 0);   // children at -45°, -22.5°, 0°, 22.5°, 45°
        Assert.Equal(2, right.SlotFrom(null, Direction.Right));
        Assert.Equal(0, right.SlotToward(Direction.UpRight));
        Assert.Equal(1, right.SlotFrom(2, Direction.Up));
        Assert.Equal(0, right.SlotFrom(0, Direction.Up));       // stays at the end
        Assert.Equal(3, right.SlotFrom(2, Direction.Down));
    }
}
