using System.Windows;
using System.Windows.Media;
using Halo.Core;
using Halo.Core.Catalog;

namespace Halo.App.Rendering;

/// <summary>
/// The Glass theme: a segmented annulus of frosted, rounded sectors around a frosted hub that
/// names the highlighted slot. The frost is a blurred snapshot of the screen behind the ring
/// (WPF can't blur other windows live); with Windows' transparency effects off, or in high
/// contrast, the sectors are solid. Folder children fan out as an outer band.
/// </summary>
internal static class GlassPainter
{
    private static readonly Dictionary<(double Inner, double Outer, double A0, double A1, double Corner), Geometry> Sectors = [];

    public static void Paint(DrawingContext dc, PaintContext p)
    {
        var m = p.Metrics;
        var a = p.Anim;
        var s = m.Scale;
        var frosted = p.Model.Backdrop is not null && SystemAppearance.TransparencyEnabled && !SystemAppearance.HighContrast;
        dc.PushTransform(new ScaleTransform(a.Scale, a.Scale, p.Center.X, p.Center.Y));
        dc.PushOpacity(a.Opacity);

        var baseShapes = Enumerable.Range(0, p.BaseRing.SlotCount).Select(i =>
        {
            var (start, end) = p.BaseGeometry.Sector(i, m.HalfGapAngle);
            return Sector(m.InnerRadius, m.OuterRadius, start, end, 8 * s);
        }).ToArray();

        dc.PushOpacity(p.BaseIsCurrent ? 1 : a.Dim);
        for (var i = 0; i < baseShapes.Length; i++)
        {
            // Segments grow out of the hub along their spokes while the ring blooms.
            if (!p.PushBloom(dc, i, p.Center, fromScale: 0)) continue;
            var mid = p.BaseGeometry.Offset(i, m.SlotCenterRadius);
            if (frosted) Frost(dc, p, [baseShapes[i]]);
            DrawSegment(dc, p, baseShapes[i], p.BaseRing[i], i, p.BaseHighlight(i), frosted, new Point(p.Center.X + mid.X, p.Center.Y + mid.Y), p.BaseIsCurrent);
            dc.Pop();
            dc.Pop();
        }
        var hub = Math.Max(a.HubBloom, 0);
        dc.PushTransform(new ScaleTransform(hub, hub, p.Center.X, p.Center.Y));
        if (frosted) Frost(dc, p, [new EllipseGeometry(new Point(0, 0), m.HubRadius, m.HubRadius)]);
        DrawHub(dc, p, frosted);
        dc.Pop();
        dc.Pop();

        if (p.Children is { } children) DrawChildren(dc, p, children, frosted);

        dc.Pop();
        dc.Pop();
    }

    private static void DrawChildren(DrawingContext dc, PaintContext p, FannedChildren children, bool frosted)
    {
        var m = p.Metrics;
        var s = m.Scale;
        var inner = m.OuterRadius + 12 * s;
        var outer = inner + m.SlotSize;
        var halfGap = m.SegmentGap / ((inner + outer) / 2) / 2;
        for (var i = 0; i < children.Ring.SlotCount; i++)
        {
            var (_, progress) = p.ChildPlacement(children, i);
            if (progress <= 0.001) continue;
            var angle = children.Arc.Angle(i);
            var shape = Sector(inner, outer, angle - children.Arc.Step / 2 + halfGap, angle + children.Arc.Step / 2 - halfGap, 8 * s);
            var grow = p.Anim.Moves ? 0.9 + 0.1 * Math.Min(progress, 1.05) : 1;
            var mid = (inner + outer) / 2;
            var centre = new Point(p.Center.X + Math.Cos(angle) * mid, p.Center.Y + Math.Sin(angle) * mid);
            dc.PushOpacity(Math.Clamp(progress * 1.3, 0, 1));
            dc.PushTransform(new ScaleTransform(grow, grow, p.Center.X, p.Center.Y));
            if (frosted) Frost(dc, p, [shape]);
            var highlight = children.IsInteractive ? p.Anim.Highlight(i) : 0;
            DrawSegment(dc, p, shape, children.Ring[i], i, highlight, frosted, centre, children.IsInteractive);
            dc.Pop();
            dc.Pop();
        }
    }

    private static void DrawSegment(DrawingContext dc, PaintContext p, Geometry shape, Slot slot, int index, double highlight, bool frosted, Point iconCentre, bool isCurrentLevel)
    {
        var m = p.Metrics;
        var s = m.Scale;
        var model = p.Model;
        var grow = p.Anim.Moves ? 1 + (m.HighlightScale - 1) * Math.Min(highlight, 1) : 1;
        var pulse = isCurrentLevel && model.Executing == index ? p.Anim.Pulse : 0;
        grow += 0.04 * pulse;
        var shake = isCurrentLevel && model.Rejected?.Slot == index ? p.Anim.ShakeOffset * 6 * s : 0;
        var ghosted = model.Mode == RingMode.Editor && isCurrentLevel && model.InheritedSlots.Contains(index);
        if (ghosted) dc.PushOpacity(0.5);
        dc.PushTransform(new TranslateTransform(shake, 0));
        dc.PushTransform(new ScaleTransform(grow, grow, p.Center.X, p.Center.Y));

        var baseFill = frosted ? p.Palette.GlassTint : p.Palette.GlassSolid;
        var tile = RingPalette.WithAlpha(p.Palette.TileColor(slot.Tint, RingTheme.Glass), 0.92);
        var fill = RingPalette.Lerp(baseFill, tile, Math.Min(highlight, 1));
        var border = SystemAppearance.HighContrast
            ? new Pen(SystemColors.WindowTextBrush, 1.5 * s)
            : new Pen(RingPalette.Brush(p.Palette.GlassBorder), 1);
        dc.PushTransform(new TranslateTransform(p.Center.X, p.Center.Y));
        dc.DrawGeometry(RingPalette.Brush(fill), border, shape);
        if (model.Mode == RingMode.Editor && isCurrentLevel && model.Selected == index)
        {
            dc.DrawGeometry(null, new Pen(RingPalette.Brush(p.Palette.Accent), 2.5 * s), shape);
        }
        if (isCurrentLevel && model.Rejected?.Slot == index && p.Anim.ShakeOffset != 0)
        {
            dc.DrawGeometry(null, new Pen(RingPalette.Brush(RingPalette.Reject), 1.5 * s), shape);
        }
        dc.Pop();

        var glyphColor = RingPalette.Lerp(p.Palette.GlassGlyph, Colors.White, Math.Min(highlight, 1));
        if (slot.IsEmpty)
        {
            if (model.Mode == RingMode.Editor)
            {
                dc.PushTransform(new TranslateTransform(iconCentre.X, iconCentre.Y));
                dc.DrawGeometry(RingPalette.Brush(p.Palette.GlassSecondary), null, p.Art.Symbol("plus", 16 * s));
                dc.Pop();
            }
        }
        else
        {
            ClassicPainter.DrawArt(dc, p, iconCentre, m.SlotSize / 2, slot, glyphColor);
            if (model.LabelMode == LabelMode.Always)
            {
                var caption = p.Text(PaintContext.Title(slot), PaintContext.Regular, 9.5 * s, RingPalette.WithAlpha(glyphColor, 0.85));
                caption.MaxTextWidth = m.SlotSize * 1.2;
                caption.MaxLineCount = 1;
                caption.Trimming = TextTrimming.CharacterEllipsis;
                caption.TextAlignment = TextAlignment.Center;
                dc.DrawText(caption, new Point(iconCentre.X - caption.MaxTextWidth / 2, iconCentre.Y + m.IconSize * 0.6));
            }
        }
        if (model.ShowNumbers && isCurrentLevel && index < 10)
        {
            var number = p.Text(((index + 1) % 10).ToString(System.Globalization.CultureInfo.InvariantCulture), PaintContext.Semibold, 9 * s,
                RingPalette.WithAlpha(glyphColor, 0.7));
            var position = iconCentre - p.Outward(iconCentre) * (m.SlotSize * 0.36);
            dc.DrawText(number, new Point(position.X - number.Width / 2, position.Y - number.Height / 2));
        }

        dc.Pop();
        dc.Pop();
        if (ghosted) dc.Pop();
    }

    private static void DrawHub(DrawingContext dc, PaintContext p, bool frosted)
    {
        var m = p.Metrics;
        var s = m.Scale;
        var model = p.Model;
        var fill = RingPalette.Lerp(frosted ? p.Palette.GlassTint : p.Palette.GlassSolid, RingPalette.HubHover, p.Anim.HubHover * 0.6);
        dc.DrawEllipse(RingPalette.Brush(fill), new Pen(RingPalette.Brush(p.Palette.GlassBorder), 1), p.Center, m.HubRadius, m.HubRadius);

        var focused = model.FocusedSlot is { } f && p.CurrentSlot(f) is { IsEmpty: false } slot ? slot : null;
        if (focused is not null && (model.LabelMode != LabelMode.None || model.Mode == RingMode.Editor))
        {
            var title = p.Text(PaintContext.Title(focused), PaintContext.Semibold, m.HubLabelFontSize, p.Palette.GlassGlyph);
            title.MaxTextWidth = m.HubRadius * 1.6;
            title.MaxLineCount = 2;
            title.Trimming = TextTrimming.CharacterEllipsis;
            title.TextAlignment = TextAlignment.Center;
            dc.PushOpacity(Math.Clamp(p.Anim.Label, 0, 1));
            dc.DrawText(title, new Point(p.Center.X - title.MaxTextWidth / 2, p.Center.Y - title.Height / 2));
            dc.Pop();
            return;
        }

        var inFolder = model.Levels.Depth > 0 || (model.Mode == RingMode.Editor && model.LevelTitle is not null);
        var glyph = p.Art.Symbol(inFolder ? "chevron.backward" : "xmark", 14 * s);
        var caption = inFolder ? model.Levels.Breadcrumb.LastOrDefault() ?? model.LevelTitle ?? "Back" : model.AppBadge?.Name ?? "Close";
        dc.PushTransform(new TranslateTransform(p.Center.X, p.Center.Y - 8 * s));
        dc.DrawGeometry(RingPalette.Brush(p.Palette.GlassSecondary), null, glyph);
        dc.Pop();
        var text = p.Text(caption, PaintContext.Regular, 10.5 * s, p.Palette.GlassSecondary);
        text.MaxTextWidth = m.HubRadius * 1.6;
        text.MaxLineCount = 1;
        text.Trimming = TextTrimming.CharacterEllipsis;
        text.TextAlignment = TextAlignment.Center;
        dc.DrawText(text, new Point(p.Center.X - text.MaxTextWidth / 2, p.Center.Y + 4 * s));
    }

    /// <summary>Draws the blurred backdrop clipped to <paramref name="shapes"/> (shapes centred on the origin).</summary>
    private static void Frost(DrawingContext dc, PaintContext p, IEnumerable<Geometry> shapes)
    {
        var clip = new GeometryGroup { FillRule = FillRule.Nonzero, Transform = new TranslateTransform(p.Center.X, p.Center.Y) };
        foreach (var shape in shapes) clip.Children.Add(shape);
        clip.Freeze();
        dc.PushClip(clip);
        dc.DrawImage(p.Model.Backdrop!, new Rect(p.Size));
        dc.Pop();
    }

    /// <summary>
    /// An annular sector from <paramref name="a0"/> to <paramref name="a1"/> (y-down radians,
    /// clockwise) with rounded corners: an inset sector united with its round-joined outline.
    /// Cached; centred on the origin.
    /// </summary>
    private static Geometry Sector(double inner, double outer, double a0, double a1, double corner)
    {
        var key = (Math.Round(inner, 2), Math.Round(outer, 2), Math.Round(a0, 4), Math.Round(a1, 4), Math.Round(corner, 2));
        if (Sectors.TryGetValue(key, out var cached)) return cached;
        corner = Math.Min(corner, (outer - inner) / 3);
        var ri = inner + corner;
        var ro = outer - corner;
        var di = corner / ri;
        var dO = corner / ro;
        var large = a1 - a0 > Math.PI;
        var core = new StreamGeometry();
        using (var g = core.Open())
        {
            g.BeginFigure(Polar(ro, a0 + dO), isFilled: true, isClosed: true);
            g.ArcTo(Polar(ro, a1 - dO), new Size(ro, ro), 0, large, SweepDirection.Clockwise, true, false);
            g.LineTo(Polar(ri, a1 - di), true, false);
            g.ArcTo(Polar(ri, a0 + di), new Size(ri, ri), 0, large, SweepDirection.Counterclockwise, true, false);
        }
        core.Freeze();
        var outline = core.GetWidenedPathGeometry(new Pen(Brushes.Black, corner * 2) { LineJoin = PenLineJoin.Round });
        var sector = Geometry.Combine(core, outline, GeometryCombineMode.Union, null);
        sector.Freeze();
        if (Sectors.Count > 512) Sectors.Clear();
        Sectors[key] = sector;
        return sector;
    }

    private static Point Polar(double radius, double angle) => new(Math.Cos(angle) * radius, Math.Sin(angle) * radius);
}
