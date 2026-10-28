namespace Halo.Core.Geometry;

/// <summary>
/// Sizes of the ring for a theme, scale and slot count, in device-independent pixels (the Mac's
/// points; Logitech's Windows ring measures the same at 100 % scaling).
/// </summary>
/// <remarks>
/// Shared by the renderer (drawing), the overlay (window size, placement, hit-testing) and the
/// editor, so all three always agree.
/// <list type="bullet">
/// <item>Classic: 46 px bubbles at radius 82.5 px around a 31 px hub; folder children fan out on an
/// outer circle at twice the radius, 22.5° apart.</item>
/// <item>Glass: a segmented annulus (outer radius 140 px, inner 0.42 × outer, 4 px gaps) around a hub
/// that shows the highlighted slot's name; folder children fan out on an outer band.</item>
/// </list>
/// </remarks>
public sealed record RingMetrics
{
    public RingMetrics(RingTheme theme, double scale, int slotCount)
    {
        var s = Math.Max(0.5, scale);
        var n = Math.Max(1, slotCount);
        Theme = theme;
        Scale = s;
        if (theme == RingTheme.Classic)
        {
            var bubble = 46 * s;
            var minGap = 17 * s;
            // Logitech's ring has 8 bubbles; with more, grow the radius so bubbles don't touch.
            var radius = Math.Max(82.5 * s, n * (bubble + minGap) / (2 * Math.PI));
            SlotSize = bubble;
            SlotCenterRadius = radius;
            OuterRadius = radius + bubble / 2;
            InnerRadius = radius - bubble / 2;
            SegmentGap = minGap;
            HubRadius = 15.5 * s;
            IconSize = 20 * s;
            AppIconSize = 37 * s;
            HubIconSize = 12 * s;
            HighlightScale = 1;
            FolderRadius = radius * 2;
            TooltipHeight = 20 * s;
            // Room for ~140 px tooltips placed radially outward of fanned-out children.
            CanvasPadding = 150 * s;
            LabelFontSize = 11 * s;
            HubLabelFontSize = 11 * s;
        }
        else
        {
            var outer = Math.Max(140 * s, n * 26 * s / (2 * Math.PI) + 90 * s);
            var inner = outer * 0.42;
            OuterRadius = outer;
            InnerRadius = inner;
            SlotSize = outer - inner;
            SlotCenterRadius = (outer + inner) / 2;
            SegmentGap = 4 * s;
            HubRadius = inner - 8 * s;
            IconSize = 24 * s;
            AppIconSize = 34 * s;
            HubIconSize = 22 * s;
            HighlightScale = 1.05;
            FolderRadius = outer + 12 * s + SlotSize / 2;
            TooltipHeight = 0;
            CanvasPadding = 40 * s;
            LabelFontSize = 10 * s;
            HubLabelFontSize = 12.5 * s;
        }
        HoldDeadZone = 16 * s;
        MaxHitRadius = OuterRadius + 60 * s;
        ClampRadius = OuterRadius * HighlightScale + (theme == RingTheme.Classic ? 40 : 16) * s;
    }

    public RingTheme Theme { get; }
    /// <summary>The user's size multiplier (Medium = 1).</summary>
    public double Scale { get; }

    // Hit-testing and placement

    /// <summary>Radius of the centre hub (a click inside it means "back" or "close").</summary>
    public double HubRadius { get; }
    /// <summary>While the trigger is held, pointer offsets shorter than this highlight nothing.</summary>
    public double HoldDeadZone { get; }
    /// <summary>In tap mode the pointer must leave the hub to highlight (so hover and click agree).</summary>
    public double TapDeadZone => HubRadius;
    /// <summary>In tap mode, pointer and clicks farther than this highlight nothing / dismiss.</summary>
    public double MaxHitRadius { get; }
    /// <summary>Angular hysteresis (radians) that keeps the highlight from flickering on a boundary.</summary>
    public double Hysteresis => 5 * Math.PI / 180;
    /// <summary>Distance from the centre to the fanned-out folder children's centres.</summary>
    public double FolderRadius { get; }
    /// <summary>Angle between neighbouring folder children (radians).</summary>
    public double ChildStep => ArcGeometry.DefaultStep;
    /// <summary>Radius around the centre that must stay on screen when placing the ring.</summary>
    public double ClampRadius { get; }

    // Drawing

    /// <summary>Distance from the centre to each slot's centre.</summary>
    public double SlotCenterRadius { get; }
    /// <summary>Classic: bubble diameter. Glass: the band's thickness.</summary>
    public double SlotSize { get; }
    public double OuterRadius { get; }
    public double InnerRadius { get; }
    /// <summary>Glass: gap between segments along the mid-line. Classic: minimum gap between bubbles.</summary>
    public double SegmentGap { get; }
    public double IconSize { get; }
    public double AppIconSize { get; }
    public double HubIconSize { get; }
    public double LabelFontSize { get; }
    public double HubLabelFontSize { get; }
    /// <summary>Height of the hover tooltip capsule (Classic).</summary>
    public double TooltipHeight { get; }
    /// <summary>Scale applied to the highlighted slot (Classic: none, like Logitech).</summary>
    public double HighlightScale { get; }
    /// <summary>Room around the fanned-out folder ring for tooltips, shadow and glow.</summary>
    public double CanvasPadding { get; }

    /// <summary>Side of the square the ring is drawn in (and the overlay window's size).</summary>
    public double CanvasSide => (FolderRadius + SlotSize / 2 + CanvasPadding) * 2;

    /// <summary>Glass segment gap as an angle at the mid-line (radians, per side).</summary>
    public double HalfGapAngle
    {
        get
        {
            var mid = (OuterRadius + InnerRadius) / 2;
            return mid > 0 ? SegmentGap / mid / 2 : 0;
        }
    }
}
