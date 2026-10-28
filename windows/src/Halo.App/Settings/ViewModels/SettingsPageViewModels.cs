using System.Diagnostics;
using System.Text.Json;
using System.Windows;
using System.Windows.Input;
using Halo.App.Platform;
using Halo.App.Rendering;
using Halo.App.Trigger;
using Halo.Core;
using Halo.Core.Interaction;
using Halo.Core.Storage;
using Microsoft.Win32;

namespace Halo.App.Settings.ViewModels;

/// <summary>One option of a radio group or menu; selecting it writes the setting.</summary>
internal sealed class Choice<T>(string title, string description, T value, Func<T> current, Action<T> choose) : ObservableObject
{
    public string Title { get; } = title;
    public string Description { get; } = description;
    public T Value { get; } = value;
    /// <summary>Optional visual for the option (an accent colour's swatch brush).</summary>
    public object? Visual { get; init; }

    public bool IsSelected
    {
        get => EqualityComparer<T>.Default.Equals(current(), Value);
        set
        {
            if (value) choose(Value);
        }
    }

    public void Refresh() => OnPropertyChanged(nameof(IsSelected));
}

/// <summary>Base for pages that edit <see cref="AppSettings"/>: refreshes every binding when the config changes.</summary>
internal abstract class SettingsPageViewModel : ObservableObject, IDisposable
{
    protected SettingsPageViewModel(AppModel model)
    {
        Model = model;
        Model.ConfigChanged += OnConfigChanged;
    }

    protected AppModel Model { get; }
    protected AppSettings Settings => Model.Settings;

    public void Dispose() => Model.ConfigChanged -= OnConfigChanged;

    protected void Change(string name, Func<AppSettings, AppSettings> edit) => Model.UpdateSettings(name, edit);

    protected virtual void Refresh() => OnPropertyChanged(string.Empty);

    private void OnConfigChanged(object? sender, ConfigChangedEventArgs e) => Refresh();
}

/// <summary>General: the trigger, how it selects, placement, app rings, start-up and the config file.</summary>
internal sealed class GeneralViewModel : SettingsPageViewModel
{
    private readonly TriggerHook _hook;
    private bool _isRecording;
    private string _recordingText = "";
    private string? _triggerMessage;

    public GeneralViewModel(AppModel model, TriggerHook hook) : base(model)
    {
        _hook = hook;
        SelectionModes =
        [
            Mode(SelectionMode.Auto, "Automatic", "Tap the shortcut to keep the ring open; hold it, point and release to choose."),
            Mode(SelectionMode.TapThenClick, "Tap, then click", "The ring stays open after the shortcut; click a slot or press its number."),
            Mode(SelectionMode.HoldAndRelease, "Hold and release", "Hold the shortcut, point at a slot and let go. Letting go in the centre cancels."),
        ];
        Placements =
        [
            new Choice<RingPlacement>("At the pointer", "", RingPlacement.Cursor, () => Settings.Placement, v => Change("Change Placement", s => s with { Placement = v })),
            new Choice<RingPlacement>("Centre of the screen", "", RingPlacement.ScreenCenter, () => Settings.Placement, v => Change("Change Placement", s => s with { Placement = v })),
        ];
        RecordCommand = new RelayCommand(ToggleRecording);
        ClearTriggerCommand = new RelayCommand(() => SetTrigger(null), () => Settings.Trigger is not null);
        RestoreTriggerCommand = new RelayCommand(() => SetTrigger(KeyCombo.DefaultTrigger));
        ImportCommand = new RelayCommand(Import);
        ExportCommand = new RelayCommand(Export);
        ResetCommand = new RelayCommand(Reset);
    }

    public IReadOnlyList<Choice<SelectionMode>> SelectionModes { get; }
    public IReadOnlyList<Choice<RingPlacement>> Placements { get; }

    // Trigger recorder

    /// <summary>The recorder button's text: the shortcut, or live feedback while recording.</summary>
    public string TriggerText => _isRecording ? _recordingText : Settings.Trigger?.DisplayString ?? "Not set";

    public string TriggerAutomationName => _isRecording ? "Recording shortcut. Press keys, or Escape to cancel." : $"Ring shortcut: {Settings.Trigger?.AccessibilityLabel ?? "not set"}. Activate to record a new one.";

    public bool IsRecording => _isRecording;

    /// <summary>A warning or error about the last recorded shortcut, or null.</summary>
    public string? TriggerMessage
    {
        get => _triggerMessage;
        private set => Set(ref _triggerMessage, value);
    }

    public ICommand RecordCommand { get; }
    public ICommand ClearTriggerCommand { get; }
    public ICommand RestoreTriggerCommand { get; }

    /// <summary>Stops recording without changing the trigger (the window lost focus).</summary>
    public void CancelRecording()
    {
        if (!_isRecording) return;
        _hook.EndRecording();
        _isRecording = false;
        Refresh();
    }

    // Behaviour

    public double HoldThreshold
    {
        get => Settings.HoldThreshold;
        set => Change("Change Hold Time", s => s with { HoldThreshold = AppSettings.HoldThresholdRange.Clamp(value) });
    }

    public double HoldThresholdMin => AppSettings.HoldThresholdRange.Min;
    public double HoldThresholdMax => AppSettings.HoldThresholdRange.Max;
    public string HoldThresholdText => $"{Settings.HoldThreshold:0.00} s";

    public bool AppRingsEnabled
    {
        get => Settings.AppRingsEnabled;
        set => Change("Change App Rings", s => s with { AppRingsEnabled = value });
    }

    public bool ClosesGaps
    {
        get => Settings.ClosesGaps;
        set => Change("Change Gaps", s => s with { ClosesGaps = value });
    }

    public bool LaunchAtLogin
    {
        get => Settings.LaunchAtLogin;
        set => Change("Change Start with Windows", s => s with { LaunchAtLogin = value });
    }

    public bool ShowTrayIcon
    {
        get => Settings.ShowMenuBarIcon;
        set => Change("Change Tray Icon", s => s with { ShowMenuBarIcon = value });
    }

    public bool ShowConfirmations
    {
        get => Settings.ShowConfirmations;
        set => Change("Change Confirmations", s => s with { ShowConfirmations = value });
    }

    // Config file

    public ICommand ImportCommand { get; }
    public ICommand ExportCommand { get; }
    public ICommand ResetCommand { get; }

    protected override void Refresh()
    {
        base.Refresh();
        foreach (var choice in SelectionModes) choice.Refresh();
        foreach (var choice in Placements) choice.Refresh();
        ((RelayCommand)ClearTriggerCommand).NotifyCanExecuteChanged();
    }

    private Choice<SelectionMode> Mode(SelectionMode mode, string title, string description) =>
        new(title, description, mode, () => Settings.SelectionMode, v => Change("Change Selection Mode", s => s with { SelectionMode = v }));

    private void ToggleRecording()
    {
        if (_isRecording)
        {
            CancelRecording();
            return;
        }
        _isRecording = true;
        _recordingText = "Press a shortcut…";
        TriggerMessage = null;
        _hook.BeginRecording(OnRecorded);
        Refresh();
    }

    private void OnRecorded(RecordedKey key)
    {
        if (!_isRecording) return;
        if (key.Vk == 0)
        {
            var held = key.Modifiers.KeyNames();
            _recordingText = held.Count == 0 ? "Press a shortcut…" : string.Join("+", held) + "+…";
            Refresh();
            return;
        }
        if (key.Modifiers == Modifiers.None && key.Vk == VirtualKeys.Escape)
        {
            CancelRecording();
            return;
        }
        if (key.Modifiers == Modifiers.None && key.Vk is VirtualKeys.Back or VirtualKeys.Delete)
        {
            CancelRecording();
            SetTrigger(null);
            return;
        }
        var combo = new KeyCombo(key.Vk, key.Modifiers, KeyLabels.Label(key.Vk));
        var problem = KeyLabels.Problem(combo, out var isError);
        if (isError)
        {
            TriggerMessage = $"{combo.DisplayString}: {problem}";
            _recordingText = "Press a shortcut…";
            Refresh();
            return;
        }
        CancelRecording();
        SetTrigger(combo);
        TriggerMessage = problem;
    }

    private void SetTrigger(KeyCombo? combo)
    {
        TriggerMessage = null;
        Change(combo is null ? "Clear Shortcut" : "Change Shortcut", s => s with { Trigger = combo });
    }

    private void Import()
    {
        var dialog = new OpenFileDialog
        {
            Title = "Import Halo Configuration",
            Filter = $"Halo configuration (*.{ConfigFile.ExportExtension};*.json)|*.{ConfigFile.ExportExtension};*.json|All files (*.*)|*.*",
        };
        if (dialog.ShowDialog() != true) return;
        try
        {
            var imported = ConfigFile.Import(File.ReadAllBytes(dialog.FileName));
            Model.Update("Import Configuration", _ => imported);
        }
        catch (Exception e) when (e is ConfigImportException or IOException or UnauthorizedAccessException)
        {
            MessageBox.Show(e.Message, "Import failed", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private void Export()
    {
        var dialog = new SaveFileDialog
        {
            Title = "Export Halo Configuration",
            FileName = $"Halo.{ConfigFile.ExportExtension}",
            Filter = $"Halo configuration (*.{ConfigFile.ExportExtension})|*.{ConfigFile.ExportExtension}",
        };
        if (dialog.ShowDialog() != true) return;
        try
        {
            File.WriteAllBytes(dialog.FileName, ConfigFile.Export(Model.Config));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException)
        {
            MessageBox.Show(e.Message, "Export failed", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private void Reset()
    {
        var answer = MessageBox.Show("Reset every ring and setting to Halo's defaults? You can undo this.", "Reset Halo",
            MessageBoxButton.OKCancel, MessageBoxImage.Warning, MessageBoxResult.Cancel);
        if (answer == MessageBoxResult.OK) Model.Update("Reset to Defaults", _ => HaloConfig.Default);
    }
}

/// <summary>Appearance: theme, size, labels, numbers, animation speed and accent colour, with a live preview.</summary>
internal sealed class AppearanceViewModel : SettingsPageViewModel
{
    public AppearanceViewModel(AppModel model, SlotArtwork artwork) : base(model)
    {
        Artwork = artwork;
        Preview = new RingViewModel(RingMode.Preview, model.Config.GlobalRing, model.Settings);
        Themes =
        [
            new("Classic", "Light bubbles around a small hub, like Logitech's Actions Ring.", RingTheme.Classic, () => Settings.Theme, v => Change("Change Theme", s => s with { Theme = v })),
            new("Glass", "A frosted, segmented ring that names the highlighted slot in its centre.", RingTheme.Glass, () => Settings.Theme, v => Change("Change Theme", s => s with { Theme = v })),
        ];
        LabelModes =
        [
            new("On hover", "", LabelMode.Hub, () => Settings.LabelMode, v => Change("Change Labels", s => s with { LabelMode = v })),
            new("Always", "", LabelMode.Always, () => Settings.LabelMode, v => Change("Change Labels", s => s with { LabelMode = v })),
            new("Never", "", LabelMode.None, () => Settings.LabelMode, v => Change("Change Labels", s => s with { LabelMode = v })),
        ];
        Accents = Enum.GetValues<RingColorPreset>().Select(p => new Choice<RingColor>(
            p == RingColorPreset.Blue ? "Windows accent" : p.ToString(), "", RingColor.FromPreset(p),
            () => Settings.Accent, v => Change("Change Accent", s => s with { Accent = v }))
        {
            Visual = RingPalette.Brush(RingPalette.Resolve(RingColor.FromPreset(p))),
        }).ToArray();
        UpdatePreview();
    }

    public SlotArtwork Artwork { get; }
    public RingViewModel Preview { get; }
    public IReadOnlyList<Choice<RingTheme>> Themes { get; }
    public IReadOnlyList<Choice<LabelMode>> LabelModes { get; }
    public IReadOnlyList<Choice<RingColor>> Accents { get; }

    public double RingScale
    {
        get => Settings.RingScale;
        set => Change("Change Ring Size", s => s with { RingScale = AppSettings.RingScaleRange.Clamp(value) });
    }

    public double RingScaleMin => AppSettings.RingScaleRange.Min;
    public double RingScaleMax => AppSettings.RingScaleRange.Max;
    public string RingScaleText => $"{Settings.RingScale * 100:0} %";

    public double AnimationSpeed
    {
        get => Settings.AnimationSpeed;
        set => Change("Change Animation Speed", s => s with { AnimationSpeed = AppSettings.AnimationSpeedRange.Clamp(Math.Round(value, 2)) });
    }

    public double AnimationSpeedMax => AppSettings.AnimationSpeedRange.Max;
    public string AnimationSpeedText => Settings.AnimationSpeed <= 0 ? "Off" : $"{Settings.AnimationSpeed:0.0}×";

    /// <summary>Windows' own switch overrides the speed; say so when it is off.</summary>
    public string? AnimationNote => SystemAppearance.AnimationsEnabled ? null : "Animation effects are off in Windows settings, so the ring cross-fades instead of moving.";

    public bool ShowSlotNumbers
    {
        get => Settings.ShowSlotNumbers;
        set => Change("Change Slot Numbers", s => s with { ShowSlotNumbers = value });
    }

    protected override void Refresh()
    {
        base.Refresh();
        foreach (var c in Themes) c.Refresh();
        foreach (var c in LabelModes) c.Refresh();
        foreach (var c in Accents) c.Refresh();
        UpdatePreview();
    }

    private void UpdatePreview()
    {
        Preview.Apply(Settings);
        Preview.Replace(new RingLevels(Model.Config.GlobalRing, Settings.ClosesGaps));
        Preview.Highlighted = Preview.Current.SlotCount > 2 ? 2 : 0;
        Preview.NotifyChanged();
    }
}

/// <summary>About: version, updates, and where the configuration lives.</summary>
internal sealed class AboutViewModel : SettingsPageViewModel
{
    public AboutViewModel(AppModel model, UpdateService updates) : base(model)
    {
        Updates = updates;
        CheckCommand = new RelayCommand(async () => await updates.CheckAsync());
        RestartCommand = new RelayCommand(updates.RestartToUpdate, () => updates.CanRestartToUpdate);
        OpenConfigFolderCommand = new RelayCommand(OpenConfigFolder);
        updates.PropertyChanged += (_, _) => ((RelayCommand)RestartCommand).NotifyCanExecuteChanged();
    }

    public UpdateService Updates { get; }
    public string VersionText => $"Version {Updates.CurrentVersion}";

    public bool ChecksForUpdates
    {
        get => Settings.ChecksForUpdates;
        set => Change("Change Update Checks", s => s with { ChecksForUpdates = value });
    }

    public ICommand CheckCommand { get; }
    public ICommand RestartCommand { get; }
    public ICommand OpenConfigFolderCommand { get; }

    private static void OpenConfigFolder()
    {
        Directory.CreateDirectory(ConfigFile.DefaultDirectory);
        using var process = Process.Start(new ProcessStartInfo("explorer.exe") { ArgumentList = { ConfigFile.DefaultDirectory } });
    }
}
