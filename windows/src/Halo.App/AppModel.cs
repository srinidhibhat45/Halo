using System.Diagnostics;
using System.Windows.Threading;
using Halo.Core;
using Halo.Core.Storage;

namespace Halo.App;

/// <summary>The config changed: the value before and after.</summary>
internal sealed class ConfigChangedEventArgs(HaloConfig old, HaloConfig current) : EventArgs
{
    public HaloConfig Old { get; } = old;
    public HaloConfig New { get; } = current;
}

/// <summary>
/// Where the configuration lives while Halo runs. Every edit goes through <see cref="Update"/>,
/// which records undo, schedules a save and raises <see cref="ConfigChanged"/>. The ring editor,
/// the settings pages and the overlay all read <see cref="Config"/> from here.
/// </summary>
internal interface IConfigStore
{
    HaloConfig Config { get; }

    /// <summary>Raised on the UI thread after every change (edit, undo, redo, import, reset).</summary>
    event EventHandler<ConfigChangedEventArgs>? ConfigChanged;

    /// <summary>Applies an edit. <paramref name="undoName"/> labels it for Undo ("Change Slot").
    /// Edits that return the same config are ignored.</summary>
    void Update(string undoName, Func<HaloConfig, HaloConfig> edit);

    bool CanUndo { get; }
    bool CanRedo { get; }
    /// <summary>Label of the edit Undo would revert, or null.</summary>
    string? UndoName { get; }
    string? RedoName { get; }
    void Undo();
    void Redo();
}

/// <summary>
/// The app's single source of truth: the loaded config (with undo/redo and a debounced save to
/// <c>%APPDATA%\Halo\config.json</c>) and session state such as <see cref="IsPaused"/>.
/// </summary>
internal sealed class AppModel : ObservableObject, IConfigStore
{
    private const int UndoLimit = 100;
    private readonly string _path;
    private readonly DispatcherTimer _saveTimer;
    private readonly List<(string Name, HaloConfig Config)> _undo = [];
    private readonly List<(string Name, HaloConfig Config)> _redo = [];
    /// <summary>Repeated edits of the same kind this close together undo as one (dragging a slider).</summary>
    private static readonly TimeSpan CoalesceWindow = TimeSpan.FromSeconds(1);
    private HaloConfig _config;
    private bool _isPaused;
    private DateTime _lastEdit;

    public AppModel(string? path = null)
    {
        _path = path ?? ConfigFile.DefaultPath;
        var loaded = ConfigFile.Load(_path);
        _config = loaded.Config;
        LoadOutcome = loaded.Outcome;
        _saveTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(400) };
        _saveTimer.Tick += (_, _) => Save();
    }

    public event EventHandler<ConfigChangedEventArgs>? ConfigChanged;

    /// <summary>Raised when saving failed (disk full, folder not writable…).</summary>
    public event Action<string>? SaveFailed;

    /// <summary>How the config was loaded (a recovered or unreadable file is worth telling the user).</summary>
    public ConfigLoadOutcome LoadOutcome { get; }

    public HaloConfig Config => _config;
    public AppSettings Settings => _config.Settings;

    /// <summary>The ring doesn't open while paused (tray › Pause Halo). Not saved.</summary>
    public bool IsPaused
    {
        get => _isPaused;
        set => Set(ref _isPaused, value);
    }

    public bool CanUndo => _undo.Count > 0;
    public bool CanRedo => _redo.Count > 0;
    public string? UndoName => _undo.Count > 0 ? _undo[^1].Name : null;
    public string? RedoName => _redo.Count > 0 ? _redo[^1].Name : null;

    public void Update(string undoName, Func<HaloConfig, HaloConfig> edit)
    {
        var next = edit(_config);
        if (next.Equals(_config)) return;
        var now = DateTime.UtcNow;
        var coalesce = _redo.Count == 0 && _undo.Count > 0 && _undo[^1].Name == undoName && now - _lastEdit < CoalesceWindow;
        if (!coalesce) _undo.Add((undoName, _config));
        if (_undo.Count > UndoLimit) _undo.RemoveAt(0);
        _redo.Clear();
        _lastEdit = now;
        Apply(next);
    }

    /// <summary>Changes settings only (the common case for the settings pages).</summary>
    public void UpdateSettings(string undoName, Func<AppSettings, AppSettings> edit) =>
        Update(undoName, config => config with { Settings = edit(config.Settings) });

    public void Undo() => Step(_undo, _redo);

    public void Redo() => Step(_redo, _undo);

    /// <summary>Writes a pending save now (on exit).</summary>
    public void Flush()
    {
        if (_saveTimer.IsEnabled) Save();
    }

    private void Step(List<(string Name, HaloConfig Config)> from, List<(string Name, HaloConfig Config)> to)
    {
        if (from.Count == 0) return;
        var (name, config) = from[^1];
        from.RemoveAt(from.Count - 1);
        to.Add((name, _config));
        Apply(config);
    }

    private void Apply(HaloConfig next)
    {
        var old = _config;
        _config = next;
        _saveTimer.Stop();
        _saveTimer.Start();
        OnPropertyChanged(nameof(Config));
        OnPropertyChanged(nameof(Settings));
        OnPropertyChanged(nameof(CanUndo));
        OnPropertyChanged(nameof(CanRedo));
        ConfigChanged?.Invoke(this, new ConfigChangedEventArgs(old, next));
    }

    private void Save()
    {
        _saveTimer.Stop();
        // Never overwrite a file we couldn't read or set aside: it may still hold the user's setup.
        if (LoadOutcome is ConfigLoadOutcome.Unreadable) return;
        try
        {
            ConfigFile.Save(_config, _path);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            Trace.TraceError($"Saving the config failed: {e}");
            SaveFailed?.Invoke(e.Message);
        }
    }
}
