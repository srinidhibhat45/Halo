using System.Windows;
using System.Windows.Media;
using Halo.Core;
using Microsoft.Win32;

namespace Halo.App.Rendering;

/// <summary>Windows appearance settings the ring follows.</summary>
internal static class SystemAppearance
{
    private const string PersonalizeKey = @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";

    /// <summary>Apps use the dark theme (Settings › Personalisation › Colours).</summary>
    public static bool IsDark => ReadDword("AppsUseLightTheme") == 0;

    /// <summary>"Transparency effects" is on.</summary>
    public static bool TransparencyEnabled => ReadDword("EnableTransparency") != 0;

    /// <summary>"Animation effects" is on (Settings › Accessibility › Visual effects).</summary>
    public static bool AnimationsEnabled => SystemParameters.ClientAreaAnimation;

    /// <summary>A high-contrast theme is active: draw solid, outlined shapes.</summary>
    public static bool HighContrast => SystemParameters.HighContrast;

    private static int ReadDword(string name)
    {
        using var key = Registry.CurrentUser.OpenSubKey(PersonalizeKey);
        return key?.GetValue(name) is int value ? value : 1;
    }
}

/// <summary>Colours of both ring themes, resolved for the current Windows appearance.</summary>
internal sealed class RingPalette
{
    public RingPalette(RingColor accent, bool dark)
    {
        IsDark = dark;
        Accent = Resolve(accent);
    }

    public bool IsDark { get; }
    public Color Accent { get; }

    // Classic (Logitech-style light bubbles on any background)
    public static readonly Color BubbleFill = Color.FromArgb(230, 243, 241, 241);
    public static readonly Color BubbleStroke = Color.FromArgb(20, 0, 0, 0);
    public static readonly Color Glyph = Color.FromRgb(0x1D, 0x1D, 0x1F);
    public static readonly Color DefaultTile = Color.FromRgb(0x11, 0x11, 0x11);
    public static readonly Color HubFill = Color.FromArgb(140, 130, 130, 135);
    public static readonly Color HubHover = Color.FromArgb(150, 0xC4, 0x2B, 0x1C);
    public static readonly Color TooltipFill = Color.FromArgb(245, 250, 250, 250);
    public static readonly Color Shadow = Color.FromArgb(31, 0, 0, 0);
    public static readonly Color Reject = Color.FromRgb(0xC4, 0x2B, 0x1C);

    // Glass
    public Color GlassTint => IsDark ? Color.FromArgb(150, 32, 32, 36) : Color.FromArgb(140, 252, 252, 252);
    public Color GlassSolid => IsDark ? Color.FromRgb(43, 43, 47) : Color.FromRgb(243, 243, 243);
    public Color GlassBorder => IsDark ? Color.FromArgb(40, 255, 255, 255) : Color.FromArgb(90, 255, 255, 255);
    public Color GlassGlyph => IsDark ? Colors.White : Color.FromRgb(0x1A, 0x1A, 0x1A);
    public Color GlassSecondary => IsDark ? Color.FromArgb(170, 255, 255, 255) : Color.FromArgb(150, 0, 0, 0);

    /// <summary>The highlight colour of a slot: its own tint, else the default tile (Classic) or the accent (Glass).</summary>
    public Color TileColor(RingColor? tint, RingTheme theme) =>
        tint is not null ? Resolve(tint) : theme == RingTheme.Classic ? DefaultTile : Accent;

    /// <summary>A preset or custom colour as sRGB. Blue follows the Windows accent colour.</summary>
    public static Color Resolve(RingColor color) => color switch
    {
        CustomColor c => Color.FromRgb(Byte(c.Red), Byte(c.Green), Byte(c.Blue)),
        PresetColor { Preset: RingColorPreset.Blue } => SystemColors.AccentColor,
        PresetColor p => p.Preset switch
        {
            RingColorPreset.Indigo => Color.FromRgb(0x58, 0x56, 0xD6),
            RingColorPreset.Purple => Color.FromRgb(0xAF, 0x52, 0xDE),
            RingColorPreset.Pink => Color.FromRgb(0xFF, 0x2D, 0x55),
            RingColorPreset.Red => Color.FromRgb(0xE8, 0x11, 0x23),
            RingColorPreset.Orange => Color.FromRgb(0xF7, 0x63, 0x0C),
            RingColorPreset.Yellow => Color.FromRgb(0xFF, 0xB9, 0x00),
            RingColorPreset.Green => Color.FromRgb(0x10, 0x7C, 0x10),
            RingColorPreset.Mint => Color.FromRgb(0x00, 0xB2, 0x94),
            RingColorPreset.Teal => Color.FromRgb(0x03, 0x83, 0x87),
            RingColorPreset.Cyan => Color.FromRgb(0x00, 0x99, 0xBC),
            RingColorPreset.Brown => Color.FromRgb(0x8E, 0x56, 0x2E),
            _ => Color.FromRgb(0x69, 0x79, 0x7E),
        },
        _ => SystemColors.AccentColor,
    };

    public static Color Lerp(Color a, Color b, double t)
    {
        t = Math.Clamp(t, 0, 1);
        return Color.FromArgb(
            (byte)Math.Round(a.A + (b.A - a.A) * t),
            (byte)Math.Round(a.R + (b.R - a.R) * t),
            (byte)Math.Round(a.G + (b.G - a.G) * t),
            (byte)Math.Round(a.B + (b.B - a.B) * t));
    }

    public static Color WithAlpha(Color c, double alpha) => Color.FromArgb((byte)Math.Round(Math.Clamp(alpha, 0, 1) * c.A), c.R, c.G, c.B);

    /// <summary>A frozen brush (brushes are created per frame for animated colours).</summary>
    public static SolidColorBrush Brush(Color c)
    {
        var brush = new SolidColorBrush(c);
        brush.Freeze();
        return brush;
    }

    private static byte Byte(double component) => (byte)Math.Round(Math.Clamp(component, 0, 1) * 255);
}
