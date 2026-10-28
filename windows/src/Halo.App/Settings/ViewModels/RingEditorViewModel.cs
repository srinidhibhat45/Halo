using System.Collections.ObjectModel;
using System.Windows.Input;
using System.Windows.Media;
using Halo.App.Rendering;
using Halo.Core;
using Halo.Core.Catalog;
using Halo.Core.Editing;
using Halo.Core.Interaction;

namespace Halo.App.Settings.ViewModels;

/// <summary>One slot of the ring being edited, for lists and the inspector.</summary>
internal sealed class SlotItemViewModel(int index, Slot slot, bool isInherited, ImageSource? appIcon)
{
    public int Index { get; } = index;
    public Slot Slot { get; } = slot;
    /// <summary>"1"…"9", "0", then blank: the number key that picks it in the ring.</summary>
    public string Number => Index < 10 ? ((Index + 1) % 10).ToString(System.Globalization.CultureInfo.InvariantCulture) : "";
    public string Title => Slot.DisplayTitle();
    public string Subtitle => Slot.Action is null ? "Empty" : IsInherited ? $"{Slot.Action.Category().Title()} · from Everywhere" : Slot.Action.Category().Title();
    public string Glyph => PickerViewModel.Glyph(Slot.DisplayIcon() is SymbolIcon s ? s.Name : Slot.Action?.DefaultSymbol() ?? "plus");
    public ImageSource? AppIcon { get; } = appIcon;
    public bool IsEmpty => Slot.IsEmpty;
    public bool IsFolder => Slot.Action is FolderAction;
    /// <summary>An app-ring slot showing the Everywhere ring's action (it fills an empty slot).</summary>
    public bool IsInherited { get; } = isInherited;
    public string? AvailabilityNote => Slot.Action?.Availability() is { IsAvailable: false } a ? a.Reason : null;
    public string AutomationName => $"Slot {Index + 1}: {Title}{(AvailabilityNote is null ? "" : ", unavailable on Windows")}";
}

/// <summary>
/// Edits one ring level (CONTRACT for the full editor; see <c>windows/ARCHITECTURE.md</c>): the
/// Everywhere ring or an app ring, or a folder inside either (<see cref="Address"/>). Every change
/// goes through <see cref="IConfigStore.Update"/>, so it is undoable and saved, and the view
/// model rebuilds itself from the store's <see cref="IConfigStore.ConfigChanged"/>.
/// </summary>
internal sealed class RingEditorViewModel : ObservableObject, IDisposable
{
    private readonly IConfigStore _store;
    private readonly IEditorServices _services;
    private RingAddress _address;
    private int? _selectedIndex;
    /// <summary>True while <see cref="Slots"/> is rebuilt: lists then report a null selection, which must not stick.</summary>
    private bool _rebuilding;

    public RingEditorViewModel(IConfigStore store, IEditorServices services, RingTarget target)
    {
        _store = store;
        _services = services;
        _address = new RingAddress(target);
        Preview = new RingViewModel(RingMode.Editor, CurrentRing, store.Config.Settings);
        ChooseActionCommand = new RelayCommand(ChooseAction, () => SelectedIndex is not null);
        ClearSlotCommand = new RelayCommand(() => Edit("Clear Slot", r => r.Cleared(SelectedIndex!.Value)), () => SelectedSlot is { IsEmpty: false });
        OpenFolderCommand = new RelayCommand(() => EnterFolder(SelectedIndex!.Value), () => SelectedSlot is { IsFolder: true });
        BackCommand = new RelayCommand(GoBack, () => IsInFolder);
        TryItCommand = new RelayCommand(() => _services.TryRing(Target));
        RemoveAppRingCommand = new RelayCommand(RemoveAppRing, () => IsAppRing);
        UndoCommand = new RelayCommand(_store.Undo, () => _store.CanUndo);
        RedoCommand = new RelayCommand(_store.Redo, () => _store.CanRedo);
        _store.ConfigChanged += OnConfigChanged;
        Rebuild(resetPreview: true);
    }

    /// <summary>Raised when the app ring this editor shows was removed (the window shows Everywhere instead).</summary>
    public event Action? Removed;

    // Navigation

    public RingTarget Target => _address.Target;
    /// <summary>The level shown: the target ring plus a folder path into it.</summary>
    public RingAddress Address => _address;
    public bool IsInFolder => _address.Path.Count > 0;
    /// <summary>"Everywhere › AI" (or the app's name first).</summary>
    public string Breadcrumb => string.Join("  ›  ", _store.Config.Breadcrumb(_address));
    public ICommand BackCommand { get; }

    /// <summary>Shows the folder at <paramref name="slot"/> of this level.</summary>
    public void EnterFolder(int slot)
    {
        var child = _address.Child(slot);
        if (_store.Config.RingAt(child) is null) return;
        _address = child;
        _selectedIndex = null;
        Rebuild(resetPreview: true);
    }

    /// <summary>Shows a level directly (Ctrl+click in the ring opens the editor here).</summary>
    public void Show(RingAddress address, int? slot)
    {
        if (address.Target != Target || _store.Config.RingAt(address) is null) return;
        _address = address;
        _selectedIndex = slot;
        Rebuild(resetPreview: true);
    }

    // The ring

    public Ring CurrentRing => _store.Config.RingAt(_address) ?? new Ring();
    public ObservableCollection<SlotItemViewModel> Slots { get; } = [];
    /// <summary>What <see cref="RingCanvas"/> draws for this level (editor mode).</summary>
    public RingViewModel Preview { get; }
    public SlotArtwork Artwork => _services.Artwork;
    public IReadOnlyList<int> SlotCountChoices { get; } = Enumerable.Range(Ring.MinSlotCount, Ring.MaxSlotCount - Ring.MinSlotCount + 1).ToArray();

    public int SlotCount
    {
        get => CurrentRing.SlotCount;
        set
        {
            if (value != CurrentRing.SlotCount) Edit("Change Slot Count", r => r.Resized(value));
        }
    }

    public ICommand TryItCommand { get; }
    public ICommand UndoCommand { get; }
    public ICommand RedoCommand { get; }

    // Selection and slot editing

    public int? SelectedIndex
    {
        get => _selectedIndex;
        set
        {
            if (!Set(ref _selectedIndex, value is { } i && i >= 0 && i < Slots.Count ? value : null)) return;
            SelectionChanged();
        }
    }

    /// <summary>The selected slot (two-way with lists).</summary>
    public SlotItemViewModel? SelectedSlot
    {
        get => _selectedIndex is { } i && i < Slots.Count ? Slots[i] : null;
        set
        {
            if (!_rebuilding) SelectedIndex = value?.Index;
        }
    }

    /// <summary>The selected slot's custom label; empty uses the action's own name.</summary>
    public string SlotLabel
    {
        get => SelectedSlot?.Slot.Title ?? "";
        set
        {
            if (SelectedIndex is not { } i) return;
            var title = string.IsNullOrWhiteSpace(value) ? null : value;
            if (title == CurrentRing[i].Title) return;
            Edit("Rename Slot", r => r.WithSlot(i, r[i] with { Title = title }));
        }
    }

    /// <summary>Only a slot with an action can be labelled.</summary>
    public bool CanEditLabel => SelectedSlot is { IsEmpty: false };

    /// <summary>Shown in an empty label box: the name the slot gets by default.</summary>
    public string SlotLabelPlaceholder => SelectedSlot?.Slot.Action?.DefaultTitle() ?? "";

    public ICommand ChooseActionCommand { get; }
    public ICommand ClearSlotCommand { get; }
    public ICommand OpenFolderCommand { get; }

    /// <summary>Puts <paramref name="action"/> on the selected slot (keeping its tint, resetting a custom label and icon).</summary>
    public void Assign(HaloAction action, string? title = null)
    {
        if (SelectedIndex is not { } i) return;
        _store.Update("Change Slot", c => c.AssigningAction(_address, i, action, title));
    }

    /// <summary>Swaps two slots (drag one onto another).</summary>
    public void Swap(int a, int b) => Edit("Move Slot", r => r.Swapped(a, b));

    /// <summary>Moves a slot, shifting the others.</summary>
    public void Move(int from, int to) => Edit("Move Slot", r => r.Moved(from, to));

    public void SetIcon(IconSpec? icon)
    {
        if (SelectedIndex is { } i) Edit("Change Icon", r => r.WithSlot(i, r[i] with { Icon = icon }));
    }

    public void SetTint(RingColor? tint)
    {
        if (SelectedIndex is { } i) Edit("Change Colour", r => r.WithSlot(i, r[i] with { Tint = tint }));
    }

    // App ring options

    public bool IsAppRing => Target is RingTarget.App;
    private AppProfile? Profile => Target is RingTarget.App app ? _store.Config.AppProfiles.FirstOrDefault(p => p.Id == app.ProfileId) : null;
    public string RingName => Profile?.AppName ?? "Everywhere";

    /// <summary>Use this ring while its app is in front.</summary>
    public bool IsEnabled
    {
        get => Profile?.IsEnabled ?? true;
        set => UpdateProfile(value ? "Turn On App Ring" : "Turn Off App Ring", p => p with { IsEnabled = value });
    }

    /// <summary>Empty slots show the Everywhere ring's action at the same position.</summary>
    public bool InheritsGlobalSlots
    {
        get => Profile?.InheritsGlobalSlots ?? false;
        set => UpdateProfile("Change App Ring", p => p with { InheritsGlobalSlots = value });
    }

    public ICommand RemoveAppRingCommand { get; }

    public void Dispose() => _store.ConfigChanged -= OnConfigChanged;

    private void ChooseAction()
    {
        if (_services.ChooseAction() is { } choice) Assign(choice.Action, choice.Title);
    }

    private void GoBack()
    {
        if (_address.Parent is not { } parent) return;
        var folderSlot = _address.Path[^1];
        _address = parent;
        _selectedIndex = folderSlot;
        Rebuild(resetPreview: true);
    }

    private void RemoveAppRing()
    {
        if (Profile is not { } profile) return;
        if (!_services.Confirm("Remove App Ring", $"Remove the ring for {profile.AppName}? Halo will show the Everywhere ring in {profile.AppName}.")) return;
        _store.Update("Remove App Ring", c => c.RemovingProfile(profile.Id));
    }

    private void Edit(string name, Func<Ring, Ring> body) => _store.Update(name, c => c.UpdatingRing(_address, body));

    private void UpdateProfile(string name, Func<AppProfile, AppProfile> body)
    {
        if (Profile is { } profile) _store.Update(name, c => c.UpdatingProfile(profile.Id, body));
    }

    private void OnConfigChanged(object? sender, ConfigChangedEventArgs e)
    {
        if (IsAppRing && Profile is null)
        {
            Removed?.Invoke();
            return;
        }
        // A folder that no longer exists (cleared, or undone): fall back to the nearest level that does.
        while (_store.Config.RingAt(_address) is null && _address.Parent is { } parent) _address = parent;
        Rebuild();
    }

    private void Rebuild(bool resetPreview = false)
    {
        var config = _store.Config;
        var ring = CurrentRing;
        var inherited = InheritedSlots(config, ring);
        _rebuilding = true;
        Slots.Clear();
        for (var i = 0; i < ring.SlotCount; i++)
        {
            var shown = inherited.Contains(i) ? config.GlobalRing[i] : ring[i];
            var icon = shown.DisplayIcon() is AppIcon app ? _services.Icons.Get(app.BundleId, (shown.Action as AppAction)?.Target.Path) : null;
            Slots.Add(new SlotItemViewModel(i, shown, inherited.Contains(i), icon));
        }
        _rebuilding = false;
        if (_selectedIndex is { } selected && selected >= ring.SlotCount) _selectedIndex = null;

        Preview.Apply(config.Settings);
        var shownRing = new Ring(Slots.Select(s => s.Slot));
        if (resetPreview) Preview.Reset(new RingLevels(shownRing));
        else Preview.Replace(new RingLevels(shownRing));
        Preview.InheritedSlots = inherited;
        Preview.LevelTitle = IsInFolder ? config.Breadcrumb(_address)[^1] : null;
        Preview.Selected = _selectedIndex;
        Preview.NotifyChanged();

        OnPropertyChanged(string.Empty);
        SelectionChanged();
    }

    private void SelectionChanged()
    {
        Preview.Selected = _selectedIndex;
        Preview.NotifyChanged();
        OnPropertyChanged(nameof(SelectedSlot));
        OnPropertyChanged(nameof(SlotLabel));
        OnPropertyChanged(nameof(SlotLabelPlaceholder));
        OnPropertyChanged(nameof(CanEditLabel));
        foreach (var command in new[] { ChooseActionCommand, ClearSlotCommand, OpenFolderCommand, BackCommand, UndoCommand, RedoCommand })
        {
            ((RelayCommand)command).NotifyCanExecuteChanged();
        }
    }

    /// <summary>App-ring slots that are empty and show the global ring's action instead.</summary>
    private HashSet<int> InheritedSlots(HaloConfig config, Ring ring)
    {
        if (Profile is not { InheritsGlobalSlots: true } || IsInFolder) return [];
        return Enumerable.Range(0, ring.SlotCount)
            .Where(i => ring[i].IsEmpty && config.GlobalRing.Contains(i) && !config.GlobalRing[i].IsEmpty)
            .ToHashSet();
    }
}
