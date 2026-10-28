using System.Collections.ObjectModel;
using System.Windows.Input;
using System.Windows.Media;
using Halo.App.Platform;
using Halo.App.Trigger;
using Halo.Core;
using Halo.Core.Editing;

namespace Halo.App.Settings.ViewModels;

/// <summary>A sidebar row: a ring (Everywhere or an app ring) or a settings page.</summary>
/// <param name="Section">"Rings" or "Settings" (the sidebar's group headings).</param>
internal sealed record SidebarItem(string Title, string Section, string Glyph, ImageSource? Icon, object Key)
{
    public string AutomationName => $"{Title}, {Section}";
}

/// <summary>
/// The settings window: a sidebar of rings and pages, and the selected page's view model
/// (<see cref="RingEditorViewModel"/>, <see cref="GeneralViewModel"/>, <see cref="AppearanceViewModel"/>
/// or <see cref="AboutViewModel"/>), rendered through data templates.
/// </summary>
internal sealed class SettingsViewModel : ObservableObject, IDisposable
{
    private const string GeneralKey = "general", AppearanceKey = "appearance", AboutKey = "about";
    private readonly AppModel _model;
    private readonly IEditorServices _services;
    private readonly Dictionary<RingTarget, RingEditorViewModel> _editors = [];
    private SidebarItem? _selectedItem;

    public SettingsViewModel(AppModel model, IEditorServices services, TriggerHook hook, UpdateService updates)
    {
        _model = model;
        _services = services;
        General = new GeneralViewModel(model, hook);
        Appearance = new AppearanceViewModel(model, services.Artwork);
        About = new AboutViewModel(model, updates);
        AddAppRingCommand = new RelayCommand(AddAppRing);
        UndoCommand = new RelayCommand(model.Undo, () => model.CanUndo);
        RedoCommand = new RelayCommand(model.Redo, () => model.CanRedo);
        _model.ConfigChanged += OnConfigChanged;
        RebuildSidebar();
        SelectedItem = SidebarItems[0];
    }

    public ObservableCollection<SidebarItem> SidebarItems { get; } = [];

    public GeneralViewModel General { get; }
    public AppearanceViewModel Appearance { get; }
    public AboutViewModel About { get; }

    public SidebarItem? SelectedItem
    {
        get => _selectedItem;
        set
        {
            if (value is null || !Set(ref _selectedItem, value)) return;
            OnPropertyChanged(nameof(SelectedPage));
        }
    }

    /// <summary>The page shown for <see cref="SelectedItem"/>.</summary>
    public object? SelectedPage => _selectedItem?.Key switch
    {
        RingTarget target => Editor(target),
        GeneralKey => General,
        AppearanceKey => Appearance,
        AboutKey => About,
        _ => null,
    };

    public ICommand AddAppRingCommand { get; }

    /// <summary>Ctrl+Z / Ctrl+Y anywhere in the window (text boxes keep their own undo).</summary>
    public RelayCommand UndoCommand { get; }
    public RelayCommand RedoCommand { get; }

    /// <summary>Shows a ring level with a slot selected (Ctrl+click in the live ring).</summary>
    public void Navigate(RingAddress address, int? slot)
    {
        SelectedItem = SidebarItems.FirstOrDefault(i => Equals(i.Key, address.Target)) ?? SidebarItems[0];
        Editor(address.Target).Show(address, slot);
    }

    public void ShowPage(string key) => SelectedItem = SidebarItems.FirstOrDefault(i => Equals(i.Key, key)) ?? SelectedItem;

    public void ShowAbout() => ShowPage(AboutKey);

    public void ShowGeneral() => ShowPage(GeneralKey);

    public void Dispose()
    {
        _model.ConfigChanged -= OnConfigChanged;
        foreach (var editor in _editors.Values) editor.Dispose();
        General.Dispose();
        Appearance.Dispose();
        About.Dispose();
    }

    private RingEditorViewModel Editor(RingTarget target)
    {
        if (_editors.TryGetValue(target, out var editor)) return editor;
        editor = new RingEditorViewModel(_model, _services, target);
        editor.Removed += () => SelectedItem = SidebarItems[0];
        _editors[target] = editor;
        return editor;
    }

    private void AddAppRing()
    {
        if (_services.ChooseApp("Add App Ring") is not { } app) return;
        if (_model.Config.ProfileIndex(app.BundleId) is { } existing)
        {
            Navigate(new RingAddress(new RingTarget.App(_model.Config.AppProfiles[existing].Id)), null);
            return;
        }
        // A new app ring starts empty and shows the Everywhere ring's actions in its empty slots,
        // so only what differs in that app needs setting up.
        var profile = _model.Config.NewProfile(app.BundleId, app.Name, copyGlobal: false) with { InheritsGlobalSlots = true };
        _model.Update("Add App Ring", c => c.AddingProfile(profile));
        Navigate(new RingAddress(new RingTarget.App(profile.Id)), null);
    }

    private void OnConfigChanged(object? sender, ConfigChangedEventArgs e)
    {
        UndoCommand.NotifyCanExecuteChanged();
        RedoCommand.NotifyCanExecuteChanged();
        if (!e.Old.AppProfiles.Select(p => (p.Id, p.AppName)).SequenceEqual(e.New.AppProfiles.Select(p => (p.Id, p.AppName)))) RebuildSidebar();
        foreach (var gone in _editors.Keys.OfType<RingTarget.App>().Where(t => e.New.AppProfiles.All(p => p.Id != t.ProfileId)).ToArray())
        {
            _editors[gone].Dispose();
            _editors.Remove(gone);
        }
    }

    private void RebuildSidebar()
    {
        var selectedKey = _selectedItem?.Key;
        SidebarItems.Clear();
        SidebarItems.Add(new SidebarItem("Everywhere", "Rings", PickerViewModel.Glyph("circle.grid.cross"), null, RingTarget.Everywhere));
        foreach (var profile in _model.Config.AppProfiles)
        {
            SidebarItems.Add(new SidebarItem(profile.AppName, "Rings", PickerViewModel.Glyph("app.dashed"), _services.Icons.Get(profile.BundleId), new RingTarget.App(profile.Id)));
        }
        SidebarItems.Add(new SidebarItem("General", "Settings", PickerViewModel.Glyph("gearshape"), null, GeneralKey));
        SidebarItems.Add(new SidebarItem("Appearance", "Settings", PickerViewModel.Glyph("circle.lefthalf.filled"), null, AppearanceKey));
        SidebarItems.Add(new SidebarItem("About", "Settings", "", null, AboutKey));
        _selectedItem = SidebarItems.FirstOrDefault(i => Equals(i.Key, selectedKey)) ?? SidebarItems[0];
        OnPropertyChanged(nameof(SelectedItem));
        OnPropertyChanged(nameof(SelectedPage));
    }
}
