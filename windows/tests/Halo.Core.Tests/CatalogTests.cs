using Halo.Core.Catalog;

namespace Halo.Core.Tests;

public class CatalogTests
{
    [Fact(DisplayName = "Template ids are unique")]
    public void UniqueIds()
    {
        var ids = ActionCatalog.All.Select(t => t.Id).ToArray();
        Assert.Equal(ids.Length, ids.Distinct().Count());
    }

    [Fact(DisplayName = "Every category has templates")]
    public void CategoriesCovered()
    {
        foreach (var category in Enum.GetValues<ActionCategory>())
        {
            Assert.NotEmpty(ActionCatalog.InCategory(category));
        }
    }

    [Fact(DisplayName = "Search matches titles and keywords, all terms required")]
    public void Search()
    {
        Assert.Contains(ActionCatalog.Search("snip"), t => t.Id == "shot.area");
        Assert.Contains(ActionCatalog.Search("mute"), t => t.Id == "media.mute");
        Assert.Equal(["shot.area.clip"], ActionCatalog.Search("copy area").Select(t => t.Id));
        Assert.Equal(ActionCatalog.All.Count, ActionCatalog.Search("").Count);
        Assert.Contains(ActionCatalog.Search("PÓWERSHELL"), t => t.Id == "script.shell");   // case and accents ignored
    }

    [Fact(DisplayName = "Every symbol the catalog and default rings use has a Fluent glyph")]
    public void SymbolsMapped()
    {
        var names = new HashSet<string>(ActionCatalog.All.Select(t => t.Symbol));
        names.UnionWith(Enum.GetValues<ActionCategory>().Select(c => c.Symbol()));
        names.UnionWith(Enum.GetValues<MediaCommand>().Select(m => m.Symbol()));
        names.UnionWith(Enum.GetValues<SystemCommand>().Select(s => s.Symbol()));
        names.UnionWith(Enum.GetValues<EditCommand>().Select(e => e.Symbol()));
        names.UnionWith(Enum.GetValues<WindowCommand>().Select(w => w.Symbol()));
        names.UnionWith(Enum.GetValues<ScreenshotMode>().Select(m => m.Symbol()));
        names.UnionWith(ActionCatalog.All.Select(t => t.Action.DefaultSymbol()));
        names.UnionWith(["folder.fill", "doc.fill", "xmark", "chevron.backward", "plus"]);
        names.UnionWith(Symbols(DefaultRings.Global()).Concat(Symbols(DefaultRings.Media())).Concat(Symbols(DefaultRings.Ai())));
        var missing = names.Where(n => !SymbolGlyphs.IsMapped(n)).Order().ToArray();
        Assert.True(missing.Length == 0, $"Unmapped symbols: {string.Join(", ", missing)}");
    }

    [Fact(DisplayName = "Glyph candidates are Private Use Area code points")]
    public void GlyphsArePrivateUse()
    {
        foreach (var name in SymbolGlyphs.Names)
        {
            Assert.All(SymbolGlyphs.Candidates(name), c => Assert.InRange(c, 0xE000, 0xF8FF));
        }
        Assert.Empty(SymbolGlyphs.Candidates("no.such.symbol"));
    }

    [Fact(DisplayName = "Mac-only kinds are shown as unavailable")]
    public void Availability()
    {
        Assert.False(ActionCatalog.Template("script.applescript")!.Availability.IsAvailable);
        Assert.False(ActionCatalog.Template("shortcut.run")!.Availability.IsAvailable);
        Assert.False(ActionCatalog.Template("system.doNotDisturb")!.Availability.IsAvailable);
        Assert.True(ActionCatalog.Template("script.shell")!.Availability.IsAvailable);
        Assert.False(ActionCatalog.Template("inapp.menu")!.Availability.IsAvailable);
        Assert.True(ActionCatalog.Template("inapp.shortcut")!.Availability.IsAvailable);
        var macro = new MacroAction(new Macro([new MacroStep(new EditAction(EditCommand.Copy)), new MacroStep(new AppleScriptAction(new ScriptSource("beep")))]));
        Assert.False(macro.Availability().IsAvailable);
    }

    [Fact(DisplayName = "Default titles read like Windows")]
    public void Titles()
    {
        Assert.Equal("Task View", new SystemAction(SystemCommand.MissionControl).DefaultTitle());
        Assert.Equal("Quit Notepad", new AppAction(DefaultRings.Notepad with { Behavior = AppBehavior.Quit }).DefaultTitle());
        Assert.Equal("example.com", new UrlAction(new WebLink("https://www.example.com/path")).DefaultTitle());
        Assert.Equal("ms-settings link", new UrlAction(new WebLink("ms-settings:display")).DefaultTitle());
        Assert.Equal("Command Prompt", new ShellAction(new ScriptSource("dir", "cmd")).DefaultTitle());
        Assert.Equal("Sends Ctrl+C to the app in front", ActionCatalog.Template("edit.copy")!.Subtitle);
        Assert.Equal("A very long first line …", new TextAction(new TextSnippet("A very long first line of text\nsecond")).DefaultTitle());
        Assert.Equal("Empty", new Slot().DisplayTitle());
        var mute = new AppShortcut("zoom.exe", "Zoom", "", new KeyCombo(0x41, Modifiers.Option, "A"));
        Assert.Equal("Zoom Shortcut", new AppShortcutAction(mute).DefaultTitle());
        Assert.Equal("command", new AppShortcutAction(mute).DefaultSymbol());
        Assert.Equal("mic.slash", new AppShortcutAction(mute with { Symbol = "mic.slash" }).DefaultSymbol());
        Assert.Equal("Show Sidebar", new MenuItemAction(new MenuItemRef("x", "X", ["View", "Show Sidebar"])).DefaultTitle());
        Assert.Equal(ActionCategory.InApp, new AppShortcutAction(mute).Category());
        Assert.Equal("Custom", new Slot(new MediaAction(MediaCommand.Mute), "  Custom ").DisplayTitle());
    }

    [Fact(DisplayName = "The default ring is the Windows twin of the Mac's")]
    public void DefaultRing()
    {
        var ring = DefaultRings.Global();
        Assert.Equal(8, ring.SlotCount);
        Assert.Equal(new ScreenshotAction(new ScreenshotOptions(ScreenshotMode.Area)), ring[0].Action);
        Assert.Equal("explorer.exe", Assert.IsType<AppAction>(ring[6].Action).Target.BundleId);
        Assert.Equal(new SystemAction(SystemCommand.LockScreen), ring[7].Action);
        Assert.Equal(6, Assert.IsType<FolderAction>(ring[5].Action).Ring.SlotCount);
        Assert.All(ring.Slots, s => Assert.True(s.Action!.Availability().IsAvailable));
    }

    [Fact(DisplayName = "Adjustable media commands step up and down")]
    public void Adjustable()
    {
        Assert.Equal(MediaCommand.VolumeDown, MediaCommand.VolumeUp.Adjusted(up: false));
        Assert.Equal(MediaCommand.BrightnessUp, MediaCommand.BrightnessDown.Adjusted(up: true));
        Assert.False(MediaCommand.Mute.IsAdjustable());
    }

    private static IEnumerable<string> Symbols(Ring ring) =>
        ring.Slots.SelectMany(slot =>
        {
            var names = new List<string>();
            if (slot.DisplayIcon() is SymbolIcon symbol) names.Add(symbol.Name);
            if (slot.Action is FolderAction folder) names.AddRange(Symbols(folder.Ring));
            return names;
        });
}
