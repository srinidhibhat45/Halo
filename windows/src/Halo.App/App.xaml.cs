using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Threading;
using Halo.App.Apps;
using Halo.App.Interop;
using Halo.App.Overlay;
using Halo.App.Platform;
using Halo.App.Rendering;
using Halo.App.Settings;
using Halo.App.Settings.ViewModels;
using Halo.App.Trigger;
using Halo.Core;
using Halo.Core.Editing;
using Halo.Core.Storage;

namespace Halo.App;

/// <summary>
/// Halo's process: a tray app with no main window. Wires the model, the keyboard hook, the
/// overlay, updates, the tray icon and the settings window, and tears them down on exit.
/// </summary>
internal partial class HaloApplication : Application
{
    private readonly SingleInstance _instance;
    private readonly bool _startedAtSignIn;
    private AppModel? _model;
    private TriggerHook? _hook;
    private OverlayController? _overlay;
    private ToastPresenter? _toasts;
    private UpdateService? _updates;
    private TrayIcon? _tray;
    private nint _trayIcon;
    private InstalledApps? _apps;
    private AppIconCache? _icons;
    private SlotArtwork? _artwork;
    private SettingsWindow? _settings;

    public HaloApplication(SingleInstance instance, bool startedAtSignIn)
    {
        _instance = instance;
        _startedAtSignIn = startedAtSignIn;
    }

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        DispatcherUnhandledException += OnUnhandledException;

        _model = new AppModel();
        _apps = new InstalledApps();
        _icons = new AppIconCache(_apps);
        _artwork = new SlotArtwork(_icons);
        _toasts = new ToastPresenter();
        _hook = new TriggerHook(Dispatcher, click => Dispatcher.BeginInvoke(() => _overlay?.OutsideClick(click.X, click.Y)));
        _overlay = new OverlayController(_model, _hook, _toasts, _icons, _artwork, (address, slot) => ShowSettings(s => s.Navigate(address, slot)));
        _updates = new UpdateService { AutomaticChecks = _model.Settings.ChecksForUpdates };
        _updates.PropertyChanged += (_, _) => UpdateTray();
        _updates.Restarting += () => _model.Flush();
        _model.ConfigChanged += OnConfigChanged;
        _model.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName == nameof(AppModel.IsPaused)) OnPausedChanged();
        };
        _model.SaveFailed += message => ShowNotice($"Halo couldn't save your settings: {message}");

        CreateTray();
        _instance.ListenForActivation(() => Dispatcher.BeginInvoke(() => ShowSettings()));
        _updates.Start();
        _ = _apps.LoadAsync();
        SyncStartWithWindows(_model.Settings.LaunchAtLogin);

        ReportStartupProblems();
        if (!_model.Settings.HasCompletedOnboarding)
        {
            // First run: show where the ring is configured and how to open it.
            _model.UpdateSettings("Finish Setup", s => s with { HasCompletedOnboarding = true });
            ShowSettings(s => s.ShowGeneral());
        }
        else if (!_startedAtSignIn)
        {
            // Started from the Start menu while not running: show the settings.
            ShowSettings();
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _model?.Flush();
        _overlay?.Dispose();
        _hook?.Dispose();
        _tray?.Dispose();
        if (_trayIcon != 0) Native.DestroyIcon(_trayIcon);
        base.OnExit(e);
    }

    /// <summary>Opens (or brings forward) Halo Settings, optionally on a page or ring.</summary>
    private void ShowSettings(Action<SettingsViewModel>? navigate = null)
    {
        if (_settings is null)
        {
            var services = new EditorServices(() => _settings, _artwork!, _icons!, _apps!, _hook!, _overlay!);
            _settings = new SettingsWindow(new SettingsViewModel(_model!, services, _hook!, _updates!));
            _settings.Closed += (_, _) => _settings = null;
        }
        navigate?.Invoke(_settings.Model);
        _settings.Present();
    }

    private void OnConfigChanged(object? sender, ConfigChangedEventArgs e)
    {
        _overlay?.SettingsChanged(e.New);
        if (e.New.Settings.LaunchAtLogin != e.Old.Settings.LaunchAtLogin) SyncStartWithWindows(e.New.Settings.LaunchAtLogin);
        if (_updates is not null) _updates.AutomaticChecks = e.New.Settings.ChecksForUpdates;
        UpdateTray();
    }

    private void OnPausedChanged()
    {
        if (_hook is not null) _hook.IsSuspended = _model!.IsPaused;
        if (_model!.IsPaused) _overlay?.Dismiss();
        UpdateTray();
    }

    private static void SyncStartWithWindows(bool enabled)
    {
        try
        {
            if (enabled != StartWithWindows.IsEnabled || enabled) StartWithWindows.Set(enabled);
        }
        catch (Exception e) when (e is UnauthorizedAccessException or System.Security.SecurityException or IOException)
        {
            Trace.TraceWarning($"Couldn't change Start with Windows: {e.Message}");
        }
    }

    // Tray

    private void CreateTray()
    {
        var ico = IconFactory.ResourceBytes("Assets/Halo.ico");
        _trayIcon = IconFactory.SmallIcon(ico, Native.GetDpiForSystem());
        _tray = new TrayIcon(_trayIcon, "Halo");
        _tray.Invoked += () => ShowSettings();
        _tray.MenuRequested += ShowTrayMenu;
        UpdateTray();
    }

    private void UpdateTray()
    {
        if (_tray is null || _model is null) return;
        var tooltip = _model.IsPaused ? "Halo (paused)" : _updates?.CanRestartToUpdate == true ? "Halo: an update is ready" : "Halo";
        _tray.Update(_trayIcon, tooltip);
        _tray.IsVisible = _model.Settings.ShowMenuBarIcon;
    }

    private void ShowTrayMenu()
    {
        var model = _model!;
        var updates = _updates!;
        var menu = new ContextMenu { Placement = PlacementMode.MousePoint };
        menu.Items.Add(Item("Show Ring", () => _overlay?.TryRing(RingTarget.Everywhere), enabled: !model.IsPaused));
        menu.Items.Add(Item("Halo Settings…", () => ShowSettings()));
        menu.Items.Add(new Separator());
        var pause = Item("Pause Halo", () => model.IsPaused = !model.IsPaused);
        pause.IsCheckable = true;
        pause.IsChecked = model.IsPaused;
        menu.Items.Add(pause);
        menu.Items.Add(updates.CanRestartToUpdate
            ? Item("Restart to Update", updates.RestartToUpdate)
            : Item("Check for Updates…", () => ShowSettings(s => s.ShowAbout()), enabled: updates.State != UpdateState.NotInstalled));
        menu.Items.Add(new Separator());
        menu.Items.Add(Item("Quit Halo", Shutdown));
        _tray!.PrepareForMenu();
        menu.IsOpen = true;
    }

    private static MenuItem Item(string header, Action onClick, bool enabled = true)
    {
        var item = new MenuItem { Header = header, IsEnabled = enabled };
        item.Click += (_, _) => onClick();
        return item;
    }

    // Problems

    private void ReportStartupProblems()
    {
        switch (_model!.LoadOutcome)
        {
            case ConfigLoadOutcome.RecoveredFromCorruption recovered:
                ShowNotice($"Your Halo settings file couldn't be read, so Halo used its backup. The damaged file was kept as {Path.GetFileName(recovered.MovedTo)}.");
                break;
            case ConfigLoadOutcome.Unreadable unreadable:
                ShowNotice($"Halo can't read its settings ({unreadable.Reason}) and is using defaults without saving.");
                break;
        }
        if (!_hook!.IsInstalled) ShowNotice("Halo couldn't watch the keyboard, so its shortcut won't open the ring. Try restarting Halo.");
    }

    private void ShowNotice(string message)
    {
        var (x, y) = Displays.Cursor();
        _toasts?.Show(0xE7BA, message, (x, y), TimeSpan.FromSeconds(6));
    }

    private void OnUnhandledException(object sender, DispatcherUnhandledExceptionEventArgs e)
    {
        // A tray utility should survive a bug in one action or page; log it and carry on.
        Trace.TraceError($"Unhandled exception: {e.Exception}");
        ShowNotice($"Something went wrong: {e.Exception.Message}");
        e.Handled = true;
    }
}
