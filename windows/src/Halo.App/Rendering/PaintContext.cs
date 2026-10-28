using System.Globalization;
using System.Windows;
using System.Windows.Media;
using Halo.Core;
using Halo.Core.Catalog;
using Halo.Core.Geometry;
using Halo.Core.Interaction;
using Halo.Core.Motion;

namespace Halo.App.Rendering;

/// <summary>Folder children drawn on the outer arc: fanned out (inside a folder) or folding back in.</summary>
internal sealed record FannedChildren(Ring Ring, ArcGeometry Arc, int Anchor, bool IsInteractive);

/// <summary>Everything a painter needs for one frame.</summary>
internal sealed class PaintContext
{
    public static readonly FontFamily TextFont = new("Segoe UI Variable Text, Segoe UI");
    public static readonly Typeface Semibold = new(TextFont, FontStyles.Normal, FontWeights.SemiBold, FontStretches.Normal);
    public static readonly Typeface Regular = new(TextFont, FontStyles.Normal, FontWeights.Normal, FontStretches.Normal);

    public PaintContext(RingViewModel model, RingAnimator anim, SlotArtwork art, RingPalette palette, Size size, double pixelsPerDip)
    {
        Model = model;
        Anim = anim;
        Art = art;
        Palette = palette;
        PixelsPerDip = pixelsPerDip;
        Size = size;
        Center = new Point(size.Width / 2, size.Height / 2);
        Layout = model.Layout;
        Metrics = Layout.Metrics;
        var fanned = Layout.IsFanned;
        BaseRing = fanned ? model.Levels.Root : model.Current;
        BaseGeometry = new RingGeometry(BaseRing.SlotCount);
        Children = fanned
            ? new FannedChildren(model.Current, Layout.ChildArc!.Value, Layout.RootAnchor!.Value, IsInteractive: true)
            : anim.Folding is { } folding ? new FannedChildren(folding.Ring, folding.Arc, folding.Anchor, IsInteractive: false) : null;
    }

    public RingViewModel Model { get; }
    public RingAnimator Anim { get; }
    public SlotArtwork Art { get; }
    public RingPalette Palette { get; }
    public double PixelsPerDip { get; }
    public Size Size { get; }
    public Point Center { get; }
    public RingLayout Layout { get; }
    public RingMetrics Metrics { get; }

    /// <summary>The full ring drawn around the hub: the root while a folder is fanned out, else the current level.</summary>
    public Ring BaseRing { get; }
    public RingGeometry BaseGeometry { get; }
    /// <summary>True when the base ring is the level being interacted with (no folder fanned out).</summary>
    public bool BaseIsCurrent => !Layout.IsFanned;
    public FannedChildren? Children { get; }

    /// <summary>Where base-ring slot <paramref name="index"/> is this frame (travelling out of the hub while the ring blooms).</summary>
    public Point BaseSlotCenter(int index)
    {
        var o = BaseGeometry.Offset(index, Metrics.SlotCenterRadius * Anim.Bloom(index));
        return new Point(Center.X + o.X, Center.Y + o.Y);
    }

    /// <summary>
    /// Pushes the bloom of base-ring slot <paramref name="index"/> (fade in, grow about
    /// <paramref name="origin"/>); returns false, pushing nothing, while the slot hasn't started.
    /// Pop twice when true.
    /// </summary>
    public bool PushBloom(DrawingContext dc, int index, Point origin, double fromScale)
    {
        var bloom = Anim.Bloom(index);
        if (bloom <= 0.001) return false;
        var scale = fromScale + (1 - fromScale) * bloom;
        dc.PushOpacity(Math.Clamp(bloom * 2.5, 0, 1));
        dc.PushTransform(new ScaleTransform(scale, scale, origin.X, origin.Y));
        return true;
    }

    /// <summary>Highlight strength of base-ring slot <paramref name="index"/>.</summary>
    public double BaseHighlight(int index)
    {
        if (BaseIsCurrent)
        {
            var folding = Children is { IsInteractive: false } c && c.Anchor == index ? Anim.Fan : 0;
            return Math.Max(Anim.Highlight(index), folding);
        }
        // An open folder's bubble stays filled with its tile colour.
        return Children?.Anchor == index ? 1 : 0;
    }

    /// <summary>Where child <paramref name="index"/> is this frame, and how far it has fanned out (0…1).</summary>
    public (Point Center, double Progress) ChildPlacement(FannedChildren children, int index)
    {
        var progress = Math.Clamp(RingMotion.Delayed(Anim.Fan, RingMotion.FanDelay(index, children.Ring.SlotCount)), 0, 1.1);
        var target = children.Arc.Offset(index, Metrics.FolderRadius);
        if (!Anim.Moves) return (new Point(Center.X + target.X, Center.Y + target.Y), progress);
        var from = BaseGeometry.Offset(children.Anchor, Metrics.SlotCenterRadius);
        return (new Point(Center.X + RingMotion.Lerp(from.X, target.X, progress), Center.Y + RingMotion.Lerp(from.Y, target.Y, progress)), progress);
    }

    /// <summary>The slot shown at <paramref name="index"/> of the interactive level, or null.</summary>
    public Slot? CurrentSlot(int index) => Model.Current.Contains(index) ? Model.Current[index] : null;

    /// <summary>Where slot <paramref name="index"/> of the interactive level is drawn.</summary>
    public Point CurrentSlotCenter(int index)
    {
        if (Children is { IsInteractive: true } children) return ChildPlacement(children, index).Center;
        return BaseSlotCenter(index);
    }

    public FormattedText Text(string text, Typeface face, double size, Color color) =>
        new(text, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, face, size, RingPalette.Brush(color), PixelsPerDip);

    /// <summary>Unit vector from the ring centre toward <paramref name="point"/> (up when at the centre).</summary>
    public Vector Outward(Point point)
    {
        var v = point - Center;
        return v.Length < 0.001 ? new Vector(0, -1) : v / v.Length;
    }

    /// <summary>
    /// A rounded capsule label placed radially outward of a bubble, <paramref name="gap"/> beyond its
    /// edge, with a small notch pointing at it (Logitech-style tooltip).
    /// </summary>
    public void Tooltip(DrawingContext dc, Point bubble, double bubbleRadius, string title, double progress, bool notch, Color fill, Color textColor, double fontSize, double height, double gap)
    {
        if (progress <= 0.01 || title.Length == 0) return;
        var s = Metrics.Scale;
        var text = Text(title, Semibold, fontSize, textColor);
        var width = Math.Min(text.Width, 220 * s) + 16 * s;
        text.MaxTextWidth = Math.Max(1, width - 16 * s);
        text.MaxLineCount = 1;
        text.Trimming = TextTrimming.CharacterEllipsis;
        var u = Outward(bubble);
        // Distance from the bubble centre to the capsule centre so its nearest edge sits `gap` away.
        var reach = Math.Abs(u.X) * width / 2 + Math.Abs(u.Y) * height / 2;
        var slide = Anim.Moves ? (1 - Math.Min(progress, 1)) * 6 * s : 0;
        var centre = bubble + u * (bubbleRadius + gap + reach - slide);
        var rect = new Rect(centre.X - width / 2, centre.Y - height / 2, width, height);

        dc.PushOpacity(Math.Clamp(progress, 0, 1));
        dc.DrawRoundedRectangle(RingPalette.Brush(RingPalette.Shadow), null, new Rect(rect.X, rect.Y + 1.5 * s, rect.Width, rect.Height), height / 2, height / 2);
        if (notch)
        {
            var tip = bubble + u * (bubbleRadius + 1.5 * s);
            var baseCentre = bubble + u * (bubbleRadius + gap + 2 * s);
            var across = new Vector(-u.Y, u.X) * 4 * s;
            var triangle = new StreamGeometry();
            using (var g = triangle.Open())
            {
                g.BeginFigure(tip, isFilled: true, isClosed: true);
                g.LineTo(baseCentre + across, false, false);
                g.LineTo(baseCentre - across, false, false);
            }
            triangle.Freeze();
            dc.DrawGeometry(RingPalette.Brush(fill), null, triangle);
        }
        dc.DrawRoundedRectangle(RingPalette.Brush(fill), null, rect, height / 2, height / 2);
        dc.DrawText(text, new Point(rect.X + 8 * s, centre.Y - text.Height / 2));
        dc.Pop();
    }

    /// <summary>Title of a slot for labels: its name, or "Empty".</summary>
    public static string Title(Slot slot) => slot.DisplayTitle();
}
