using System.Globalization;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Halo.App.Apps;
using Halo.Core;
using Halo.Core.Catalog;

namespace Halo.App.Rendering;

/// <summary>What to draw for a slot's icon.</summary>
internal abstract record SlotArt
{
    private SlotArt() { }

    /// <summary>A vector glyph centred on (0, 0), filled with the theme's glyph colour.</summary>
    public sealed record GlyphArt(Geometry Geometry) : SlotArt;

    /// <summary>A bitmap (app icon or custom image) drawn in a square.</summary>
    public sealed record ImageArt(ImageSource Image, bool ClipToCircle) : SlotArt;
}

/// <summary>
/// Turns icons into drawable art: Segoe Fluent Icons glyphs for symbols, the shell's icons for
/// apps, decoded PNGs for custom images and outlines for emoji. Glyph geometry is cached by code
/// point and size; images by content.
/// </summary>
internal sealed class SlotArtwork
{
    private static readonly string[] IconFonts = ["Segoe Fluent Icons", "Segoe MDL2 Assets"];
    private readonly Dictionary<(int CodePoint, double Size), Geometry> _glyphs = [];
    private readonly Dictionary<(string Text, double Size), Geometry> _emoji = [];
    private readonly Dictionary<ImageIcon, ImageSource?> _images = [];
    private readonly AppIconCache _appIcons;
    private readonly Typeface? _iconFace;
    private readonly GlyphTypeface? _iconGlyphs;

    public SlotArtwork(AppIconCache appIcons)
    {
        _appIcons = appIcons;
        foreach (var family in IconFonts)
        {
            var face = new Typeface(new FontFamily(family), FontStyles.Normal, FontWeights.Normal, FontStretches.Normal);
            if (!face.TryGetGlyphTypeface(out var glyphs)) continue;
            _iconFace = face;
            _iconGlyphs = glyphs;
            break;
        }
    }

    /// <summary>The art for a slot at icon size <paramref name="size"/>, or null for an empty slot.</summary>
    public SlotArt? For(Slot slot, double size, double appIconSize)
    {
        switch (slot.DisplayIcon())
        {
            case SymbolIcon symbol:
                return new SlotArt.GlyphArt(Symbol(symbol.Name, size));
            case AppIcon app:
                var appTarget = (slot.Action as AppAction)?.Target;
                var icon = _appIcons.Get(app.BundleId, appTarget?.Path);
                return icon is not null
                    ? new SlotArt.ImageArt(icon, ClipToCircle: false)
                    : new SlotArt.GlyphArt(Symbol(slot.Action?.DefaultSymbol() ?? "app.dashed", size));
            case ImageIcon image:
                return Image(image) is { } source ? new SlotArt.ImageArt(source, ClipToCircle: true) : new SlotArt.GlyphArt(Symbol("doc", size));
            case EmojiIcon emoji:
                return new SlotArt.GlyphArt(Emoji(emoji.Text, size * 1.1));
            default:
                return null;
        }
    }

    /// <summary>The glyph for an SF Symbols name (first code point the icon font has), centred on (0, 0).</summary>
    public Geometry Symbol(string name, double size)
    {
        var candidates = SymbolGlyphs.Candidates(name);
        var codePoint = candidates.FirstOrDefault(Has);
        return Glyph(codePoint != 0 ? codePoint : SymbolGlyphs.FallbackGlyph, size);
    }

    /// <summary>A glyph of the icon font by code point, centred on (0, 0).</summary>
    public Geometry Glyph(int codePoint, double size)
    {
        if (_glyphs.TryGetValue((codePoint, size), out var cached)) return cached;
        var geometry = _iconFace is null
            ? Geometry.Empty
            : Outline(char.ConvertFromUtf32(codePoint), _iconFace, size);
        _glyphs[(codePoint, size)] = geometry;
        return geometry;
    }

    /// <summary>Outlined text centred on (0, 0) (labels drawn as geometry so colours can animate cheaply).</summary>
    public static Geometry Outline(string text, Typeface face, double size)
    {
        var formatted = new FormattedText(text, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, face, size, Brushes.Black, 1.0);
        var geometry = formatted.BuildGeometry(new Point(0, 0));
        var bounds = geometry.Bounds;
        if (bounds.IsEmpty) return Geometry.Empty;
        geometry.Transform = new TranslateTransform(-(bounds.Left + bounds.Width / 2), -(bounds.Top + bounds.Height / 2));
        geometry.Freeze();
        return geometry;
    }

    private bool Has(int codePoint) => _iconGlyphs?.CharacterToGlyphMap.ContainsKey(codePoint) == true;

    private Geometry Emoji(string text, double size)
    {
        if (_emoji.TryGetValue((text, size), out var cached)) return cached;
        var face = new Typeface(new FontFamily("Segoe UI Emoji"), FontStyles.Normal, FontWeights.Normal, FontStretches.Normal);
        var geometry = Outline(text, face, size);
        _emoji[(text, size)] = geometry;
        return geometry;
    }

    private ImageSource? Image(ImageIcon icon)
    {
        if (_images.TryGetValue(icon, out var cached)) return cached;
        ImageSource? source = null;
        try
        {
            using var stream = new MemoryStream(icon.Png);
            var bitmap = new BitmapImage();
            bitmap.BeginInit();
            bitmap.CacheOption = BitmapCacheOption.OnLoad;
            bitmap.DecodePixelWidth = 128;
            bitmap.StreamSource = stream;
            bitmap.EndInit();
            bitmap.Freeze();
            source = bitmap;
        }
        catch (Exception e) when (e is NotSupportedException or ArgumentException or IOException or FileFormatException)
        {
            source = null;
        }
        _images[icon] = source;
        return source;
    }
}
