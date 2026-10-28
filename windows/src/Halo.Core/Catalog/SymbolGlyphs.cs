namespace Halo.Core.Catalog;

/// <summary>
/// Segoe Fluent Icons glyphs for the SF Symbols names used in configs, so a ring designed on the
/// Mac draws sensibly on Windows and vice versa.
/// </summary>
/// <remarks>
/// Each name maps to code points in order of preference: newer Fluent glyphs first (e.g. the
/// sparkle family), then a long-standing glyph present in every Windows 11 build and in Segoe MDL2
/// Assets. The renderer draws the first one its font has. Names not listed draw
/// <see cref="FallbackGlyph"/>.
/// </remarks>
public static class SymbolGlyphs
{
    /// <summary>Segoe Fluent Icons "Favicon" (a generic page glyph).</summary>
    public const int FallbackGlyph = 0xE737;

    private static readonly Dictionary<string, int[]> Map = new(StringComparer.Ordinal)
    {
        // Categories and hub
        ["square.grid.2x2"] = [0xED35, 0xE71D],
        ["globe"] = [0xE774],
        ["folder"] = [0xE8B7],
        ["folder.fill"] = [0xE8D5, 0xE8B7],
        ["playpause"] = [0xE768],
        ["camera.viewfinder"] = [0xE722],
        ["gearshape"] = [0xE713],
        ["gearshape.fill"] = [0xE713],
        ["doc.on.clipboard"] = [0xE77F],
        ["macwindow"] = [0xF7ED, 0xE78B],
        ["command"] = [0xEDA7, 0xE765],
        ["square.2.layers.3d"] = [0xE81E],
        ["square.2.layers.3d.fill"] = [0xE81E],
        ["terminal"] = [0xE756],
        ["terminal.fill"] = [0xE756],
        ["text.cursor"] = [0xF1BB, 0xE8D2],
        ["sparkles"] = [0xEAB7, 0xE945],
        ["sparkle"] = [0xF1BA, 0xE734],
        ["circle.grid.cross"] = [0xEA3A],
        ["circle.grid.cross.fill"] = [0xEA3A],
        ["wand.and.stars"] = [0xE945],
        ["xmark"] = [0xE711],
        ["chevron.backward"] = [0xE76B],
        ["plus"] = [0xE710],
        ["ellipsis"] = [0xE712],

        // In-app actions
        ["app.badge.checkmark"] = [0xECAA],
        ["command.square"] = [0xEDA7, 0xE765],
        ["filemenu.and.selection"] = [0xE700],

        // Apps, web and files
        ["app.badge"] = [0xECAA],
        ["app.dashed"] = [0xECAA],
        ["app.connected.to.app.below.fill"] = [0xE8F9],
        ["xmark.app"] = [0xE8BB],
        ["doc"] = [0xE8A5],
        ["doc.fill"] = [0xE8A5],
        ["doc.text"] = [0xE7C3],
        ["arrow.down.circle"] = [0xE896],
        ["house"] = [0xE80F],
        ["square.and.pencil"] = [0xE70B],
        ["calendar"] = [0xE787],
        ["applescript.fill"] = [0xE943],

        // Media
        ["playpause.fill"] = [0xE768],
        ["forward.fill"] = [0xE893],
        ["backward.fill"] = [0xE892],
        ["speaker.wave.3.fill"] = [0xE995],
        ["speaker.wave.1.fill"] = [0xE993],
        ["speaker.slash.fill"] = [0xE74F],
        ["sun.max.fill"] = [0xE706],
        ["sun.min.fill"] = [0xEC8A, 0xE706],
        ["music.note"] = [0xEC4F, 0xE8D6],

        // Screenshots
        ["rectangle.dashed"] = [0xF407, 0xE8B3],
        ["rectangle.dashed.and.paperclip"] = [0xE8C8],
        ["display"] = [0xE7FB, 0xE7F4],

        // System
        ["rectangle.3.group"] = [0xE7C4],
        ["rectangle.stack"] = [0xE8F9],
        ["menubar.dock.rectangle"] = [0xE7F4],
        ["square.grid.3x3.fill"] = [0xE71D],
        ["bell.badge"] = [0xE7E7, 0xEA8F],
        ["magnifyingglass"] = [0xE721],
        ["waveform"] = [0xF8B4, 0xEFA9],
        ["lock.fill"] = [0xE72E],
        ["moon.fill"] = [0xE708],
        ["powersleep"] = [0xE7E8],
        ["sparkles.tv"] = [0xE7F4],
        ["face.smiling"] = [0xE76E],
        ["mic.fill"] = [0xE720],
        ["circle.lefthalf.filled"] = [0xE7A1],
        ["moon.circle.fill"] = [0xE7ED, 0xE708],
        ["xmark.octagon.fill"] = [0xF120, 0xE9D9],
        ["switch.2"] = [0xE91C],

        // Edit
        ["doc.on.doc"] = [0xE8C8],
        ["scissors"] = [0xE8C6],
        ["doc.plaintext"] = [0xE77F],
        ["arrow.uturn.backward"] = [0xE7A7],
        ["arrow.uturn.forward"] = [0xE7A6],
        ["selection.pin.in.out"] = [0xE8B3],
        ["text.magnifyingglass"] = [0xE71E],

        // Windows
        ["rectangle.lefthalf.filled"] = [0xE90C],
        ["rectangle.righthalf.filled"] = [0xE90D],
        ["rectangle.tophalf.filled"] = [0xE90E],
        ["rectangle.bottomhalf.filled"] = [0xE90E],
        ["rectangle.inset.filled"] = [0xE922],
        ["rectangle.center.inset.filled"] = [0xE73F],
        ["minus.rectangle"] = [0xE921],
        ["arrow.up.left.and.arrow.down.right"] = [0xE740],
        ["display.2"] = [0xEE4D, 0xE7F4],
        ["xmark.rectangle"] = [0xE8BB],
        ["rectangle.split.2x1"] = [0xF0E2, 0xE8A9],

        // AI
        ["text.append"] = [0xEB78, 0xE8A5],
        ["checkmark.seal"] = [0xE930],
        ["lightbulb"] = [0xEA80],
        ["character.bubble"] = [0xF1D4, 0xE8C1],
        ["arrowshape.turn.up.left"] = [0xE97A],
    };

    /// <summary>All mapped symbol names (for icon pickers).</summary>
    public static IReadOnlyCollection<string> Names => Map.Keys;

    /// <summary>Code points for <paramref name="symbolName"/>, best first; empty when unmapped.</summary>
    public static IReadOnlyList<int> Candidates(string symbolName) =>
        Map.TryGetValue(symbolName, out var glyphs) ? glyphs : [];

    public static bool IsMapped(string symbolName) => Map.ContainsKey(symbolName);
}
