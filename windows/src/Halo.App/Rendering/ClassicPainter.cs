using System.Windows;
using System.Windows.Media;
using Halo.Core;
using Halo.Core.Catalog;
using Halo.Core.Motion;

namespace Halo.App.Rendering;

/// <summary>
/// The Classic theme, after Logitech's Actions Ring: light round bubbles around a small grey hub
/// with ×; the highlighted bubble fills with its tile colour (near-black by default) and its glyph
/// turns white; a tooltip slides out radially; folder bubbles carry an outward tab and fan their
/// children out on an outer arc while the root ring dims.
/// </summary>
internal static class ClassicPainter
{
    private static readonly RadialGradientBrush ShadowBrush = CreateShadowBrush();
    private static readonly Pen BubblePen = Frozen(new Pen(RingPalette.Brush(RingPalette.BubbleStroke), 0.75));

    public static void Paint(DrawingContext dc, PaintContext p)
    {
        var a = p.Anim;
        dc.PushTransform(new ScaleTransform(a.Scale, a.Scale, p.Center.X, p.Center.Y));
        dc.PushOpacity(a.Opacity);

        // The base ring (dimmed behind a fanned-out folder) and the hub.
        dc.PushOpacity(p.BaseIsCurrent ? 1 : a.Dim);
        for (var i = 0; i < p.BaseRing.SlotCount; i++)
        {
            var centre = p.BaseSlotCenter(i);
            if (!p.PushBloom(dc, i, centre, fromScale: 0.4)) continue;
            DrawBubble(dc, p, centre, p.BaseRing[i], i, p.BaseHighlight(i), p.BaseIsCurrent);
            dc.Pop();
            dc.Pop();
        }
        var hub = Math.Max(a.HubBloom, 0);
        dc.PushTransform(new ScaleTransform(hub, hub, p.Center.X, p.Center.Y));
        DrawHub(dc, p);
        dc.Pop();
        dc.Pop();

        if (p.Children is { } children)
        {
            for (var i = 0; i < children.Ring.SlotCount; i++)
            {
                var (centre, progress) = p.ChildPlacement(children, i);
                if (progress <= 0.001) continue;
                var highlight = children.IsInteractive ? a.Highlight(i) : 0;
                dc.PushOpacity(Math.Clamp(progress * 1.4, 0, 1));
                var scale = a.Moves ? 0.6 + 0.4 * Math.Min(progress, 1.05) : 1;
                dc.PushTransform(new ScaleTransform(scale, scale, centre.X, centre.Y));
                DrawBubble(dc, p, centre, children.Ring[i], i, highlight, children.IsInteractive);
                dc.Pop();
                dc.Pop();
            }
        }

        DrawLabels(dc, p);
        dc.Pop();
        dc.Pop();
    }

    /// <param name="isCurrentLevel">The slot belongs to the level being interacted with (rejects, pulses, numbers and selection apply).</param>
    private static void DrawBubble(DrawingContext dc, PaintContext p, Point centre, Slot slot, int index, double highlight, bool isCurrentLevel)
    {
        var m = p.Metrics;
        var s = m.Scale;
        var r = m.SlotSize / 2;
        var model = p.Model;
        if (isCurrentLevel && model.Rejected is { } rejected && rejected.Slot == index)
        {
            centre.X += p.Anim.ShakeOffset * 6 * s;
        }
        var pulse = isCurrentLevel && model.Executing == index ? p.Anim.Pulse : 0;
        var ghosted = model.Mode == RingMode.Editor && isCurrentLevel && model.InheritedSlots.Contains(index);
        if (ghosted) dc.PushOpacity(0.5);
        dc.PushTransform(new ScaleTransform(1 + (RingMotion.PulseScale - 1) * pulse, 1 + (RingMotion.PulseScale - 1) * pulse, centre.X, centre.Y));

        if (slot.IsEmpty)
        {
            DrawEmpty(dc, p, centre, r, highlight);
        }
        else
        {
            var tile = p.Palette.TileColor(slot.Tint, RingTheme.Classic);
            var fill = RingPalette.Lerp(RingPalette.BubbleFill, tile, Math.Min(highlight, 1));
            if (pulse > 0) fill = RingPalette.Lerp(fill, Colors.White, 0.25 * pulse);
            dc.DrawEllipse(ShadowBrush, null, new Point(centre.X, centre.Y + 2 * s), r + 4 * s, r + 4 * s);

            var outward = p.Outward(centre);
            if (slot.Action is FolderAction)
            {
                var tabRadius = r * 0.32;
                var tabCentre = centre + outward * r * 0.92;
                var shape = new CombinedGeometry(GeometryCombineMode.Union,
                    new EllipseGeometry(centre, r, r), new EllipseGeometry(tabCentre, tabRadius, tabRadius));
                shape.Freeze();
                dc.DrawGeometry(RingPalette.Brush(fill), BubblePen, shape);
                var dots = p.Art.Symbol("ellipsis", 9 * s);
                dc.PushTransform(new TranslateTransform(tabCentre.X, tabCentre.Y));
                dc.DrawGeometry(RingPalette.Brush(RingPalette.Lerp(RingPalette.Glyph, Colors.White, highlight)), null, dots);
                dc.Pop();
            }
            else
            {
                dc.DrawEllipse(RingPalette.Brush(fill), BubblePen, centre, r, r);
            }

            DrawArt(dc, p, centre, r, slot, RingPalette.Lerp(RingPalette.Glyph, Colors.White, Math.Min(highlight, 1)));

            if (slot.Action is MediaAction media && media.Command.IsAdjustable())
            {
                var dot = centre + outward * (r - 1.5 * s);
                dc.DrawEllipse(RingPalette.Brush(RingPalette.Lerp(RingPalette.Glyph, Colors.White, highlight)), null, dot, 2.5 * s, 2.5 * s);
            }
        }

        if (model.ShowNumbers && isCurrentLevel && index < 10) DrawNumber(dc, p, centre, r, index);

        if (isCurrentLevel && model.Rejected is { } reject && reject.Slot == index && p.Anim.ShakeOffset != 0)
        {
            dc.DrawEllipse(null, new Pen(RingPalette.Brush(RingPalette.Reject), 1.5 * s), centre, r, r);
        }

        if (model.Mode == RingMode.Editor && isCurrentLevel && model.Selected == index)
        {
            dc.DrawEllipse(null, new Pen(RingPalette.Brush(p.Palette.Accent), 2.5 * s), centre, r + 4 * s, r + 4 * s);
        }

        if (SystemAppearance.HighContrast && highlight > 0.5)
        {
            dc.DrawEllipse(null, new Pen(SystemColors.HighlightBrush, 2 * s), centre, r + 2 * s, r + 2 * s);
        }

        dc.Pop();
        if (ghosted) dc.Pop();
    }

    private static void DrawEmpty(DrawingContext dc, PaintContext p, Point centre, double r, double highlight)
    {
        var s = p.Metrics.Scale;
        var editor = p.Model.Mode == RingMode.Editor;
        var pen = new Pen(RingPalette.Brush(Color.FromArgb((byte)(editor ? 150 : 90), 128, 128, 128)), 1.5 * s)
        {
            DashStyle = new DashStyle([3, 2.5], 0),
        };
        var fill = highlight > 0 ? RingPalette.Brush(RingPalette.WithAlpha(RingPalette.BubbleFill, 0.5 * highlight)) : null;
        dc.DrawEllipse(fill, pen, centre, r - 1, r - 1);
        if (!editor) return;
        var plus = p.Art.Symbol("plus", 14 * s);
        dc.PushTransform(new TranslateTransform(centre.X, centre.Y));
        dc.DrawGeometry(RingPalette.Brush(Color.FromArgb(170, 128, 128, 128)), null, plus);
        dc.Pop();
    }

    /// <summary>Draws a slot's icon centred in its bubble: a glyph in <paramref name="glyphColor"/>, or an image.</summary>
    public static void DrawArt(DrawingContext dc, PaintContext p, Point centre, double r, Slot slot, Color glyphColor)
    {
        var m = p.Metrics;
        switch (p.Art.For(slot, m.IconSize, m.AppIconSize))
        {
            case SlotArt.GlyphArt glyph:
                dc.PushTransform(new TranslateTransform(centre.X, centre.Y));
                dc.DrawGeometry(RingPalette.Brush(glyphColor), null, glyph.Geometry);
                dc.Pop();
                break;
            case SlotArt.ImageArt image:
                var side = image.ClipToCircle ? r * 2 - 4 * m.Scale : Math.Min(m.AppIconSize * 0.82, r * 2 - 6 * m.Scale);
                var rect = new Rect(centre.X - side / 2, centre.Y - side / 2, side, side);
                if (image.ClipToCircle) dc.PushClip(new EllipseGeometry(centre, side / 2, side / 2));
                dc.DrawImage(image.Image, rect);
                if (image.ClipToCircle) dc.Pop();
                break;
        }
    }

    private static void DrawNumber(DrawingContext dc, PaintContext p, Point centre, double r, int index)
    {
        var s = p.Metrics.Scale;
        var position = centre - p.Outward(centre) * (r - 2 * s);
        dc.DrawEllipse(RingPalette.Brush(Color.FromArgb(220, 110, 110, 115)), null, position, 6 * s, 6 * s);
        var text = p.Text(((index + 1) % 10).ToString(System.Globalization.CultureInfo.InvariantCulture), PaintContext.Semibold, 8 * s, Colors.White);
        dc.DrawText(text, new Point(position.X - text.Width / 2, position.Y - text.Height / 2));
    }

    private static void DrawHub(DrawingContext dc, PaintContext p)
    {
        var m = p.Metrics;
        var s = m.Scale;
        var hover = p.Anim.HubHover;
        var fill = RingPalette.Lerp(RingPalette.HubFill, RingPalette.HubHover, hover);
        dc.DrawEllipse(RingPalette.Brush(fill), null, p.Center, m.HubRadius, m.HubRadius);
        var inFolder = p.Model.Levels.Depth > 0 || (p.Model.Mode == RingMode.Editor && p.Model.LevelTitle is not null);
        var glyph = p.Art.Symbol(inFolder ? "chevron.backward" : "xmark", m.HubIconSize);
        dc.PushTransform(new TranslateTransform(p.Center.X, p.Center.Y));
        dc.DrawGeometry(Brushes.White, null, glyph);
        dc.Pop();

        if (p.Model.AppBadge?.Icon is { } badge)
        {
            var side = 14 * s;
            var corner = p.Center + new Vector(m.HubRadius * 0.62, m.HubRadius * 0.62);
            dc.DrawImage(badge, new Rect(corner.X - side / 2, corner.Y - side / 2, side, side));
        }
    }

    private static void DrawLabels(DrawingContext dc, PaintContext p)
    {
        var m = p.Metrics;
        var s = m.Scale;
        var r = m.SlotSize / 2;
        switch (p.Model.LabelMode)
        {
            case LabelMode.Hub when p.Anim.LabelSlot is { } slot && p.CurrentSlot(slot) is { } shown:
                p.Tooltip(dc, p.CurrentSlotCenter(slot), r, PaintContext.Title(shown), p.Anim.Label, notch: true,
                    RingPalette.TooltipFill, RingPalette.Glyph, m.LabelFontSize, m.TooltipHeight, 6 * s);
                break;
            case LabelMode.Always:
                for (var i = 0; i < p.Model.Current.SlotCount; i++)
                {
                    var slot = p.Model.Current[i];
                    if (slot.IsEmpty) continue;
                    var emphasis = 0.85 + 0.15 * p.Anim.Highlight(i);
                    p.Tooltip(dc, p.CurrentSlotCenter(i), r, PaintContext.Title(slot), emphasis, notch: false,
                        RingPalette.TooltipFill, RingPalette.Glyph, 10 * s, 18 * s, 4 * s);
                }
                break;
        }
    }

    private static RadialGradientBrush CreateShadowBrush()
    {
        var brush = new RadialGradientBrush
        {
            GradientStops =
            {
                new GradientStop(RingPalette.Shadow, 0.72),
                new GradientStop(Color.FromArgb(0, 0, 0, 0), 1.0),
            },
        };
        brush.Freeze();
        return brush;
    }

    private static Pen Frozen(Pen pen)
    {
        pen.Freeze();
        return pen;
    }
}
