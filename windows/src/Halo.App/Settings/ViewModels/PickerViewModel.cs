using System.Collections.ObjectModel;
using System.Windows.Media;
using Halo.App.Apps;
using Halo.Core;
using Halo.Core.Catalog;

namespace Halo.App.Settings.ViewModels;

/// <summary>One row of a searchable picker (an action template, an installed app…).</summary>
/// <param name="Group">Heading the row is listed under.</param>
/// <param name="Glyph">Segoe Fluent Icons character for the row, when it has no <paramref name="Icon"/>.</param>
/// <param name="Note">Why the row can't be chosen, or null.</param>
/// <param name="Payload">What choosing it means: an <see cref="ActionTemplate"/>, an <see cref="InstalledApp"/>, …</param>
internal sealed record PickerItem(string Title, string Subtitle, string Group, string Glyph, ImageSource? Icon, string? Note, object Payload, IReadOnlyList<string> Keywords)
{
    public bool IsEnabled => Note is null;

    /// <summary>For screen readers: title, subtitle and why it's unavailable.</summary>
    public string AutomationName => Note is null ? $"{Title}, {Subtitle}" : $"{Title}, unavailable: {Note}";

    public bool Matches(string query) => ActionCatalog.Matches(query, [Title, Subtitle, Group, .. Keywords]);
}

/// <summary>
/// A search box over a list of <see cref="PickerItem"/>s (CONTRACT: the action library and the
/// app chooser both use it; the full editor may host it as a side panel instead of a dialog).
/// </summary>
internal sealed class PickerViewModel : ObservableObject
{
    private readonly List<PickerItem> _all;
    private string _query = "";
    private PickerItem? _selected;

    public PickerViewModel(string title, IEnumerable<PickerItem> items)
    {
        Title = title;
        _all = items.ToList();
        Refilter();
    }

    public string Title { get; }

    /// <summary>The rows matching <see cref="Query"/>, in catalog order.</summary>
    public ObservableCollection<PickerItem> Items { get; } = [];

    public string Query
    {
        get => _query;
        set
        {
            if (Set(ref _query, value)) Refilter();
        }
    }

    public PickerItem? Selected
    {
        get => _selected;
        set => Set(ref _selected, value);
    }

    /// <summary>Adds rows that arrive later (installed apps are scanned in the background).</summary>
    public void AddItems(IEnumerable<PickerItem> items)
    {
        _all.AddRange(items);
        Refilter();
    }

    private void Refilter()
    {
        var keep = Selected;
        Items.Clear();
        foreach (var item in _all.Where(i => i.Matches(_query))) Items.Add(item);
        Selected = keep is not null && Items.Contains(keep) ? keep : Items.FirstOrDefault(i => i.IsEnabled);
    }

    /// <summary>Rows for every catalog template, Mac-only ones shown but not choosable.</summary>
    public static IEnumerable<PickerItem> Templates() =>
        ActionCatalog.All.Select(t => new PickerItem(
            t.Title, t.Subtitle, t.Category.Title(), Glyph(t.Symbol), null,
            t.Availability.IsAvailable ? null : t.Availability.Reason, t, t.SearchKeywords));

    /// <summary>Rows for apps (running first, then the Start menu), choosing opens them.</summary>
    public static IEnumerable<PickerItem> Apps(IEnumerable<InstalledApp> apps, AppIconCache icons, string group) =>
        apps.Select(a => new PickerItem(a.Name, a.BundleId, group, Glyph("app.dashed"), icons.Get(a), null, a, [a.BundleId]));

    /// <summary>The most compatible Fluent glyph for a symbol name, as text.</summary>
    public static string Glyph(string symbol)
    {
        var candidates = SymbolGlyphs.Candidates(symbol);
        return char.ConvertFromUtf32(candidates.Count > 0 ? candidates[^1] : SymbolGlyphs.FallbackGlyph);
    }
}
