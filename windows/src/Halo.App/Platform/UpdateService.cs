using System.Diagnostics;
using System.Net.Http;
using System.Reflection;
using System.Windows.Threading;
using Velopack;
using Velopack.Sources;

namespace Halo.App.Platform;

internal enum UpdateState
{
    /// <summary>Not checked yet.</summary>
    Idle,
    /// <summary>Running from a build folder, not installed with Setup: updates are off.</summary>
    NotInstalled,
    Checking,
    Downloading,
    UpToDate,
    /// <summary>An update is downloaded: restart to apply it.</summary>
    ReadyToRestart,
    Failed,
}

/// <summary>
/// Over-the-air updates from GitHub Releases with Velopack: checks on launch and daily (when
/// <c>checksForUpdates</c> is on, or when asked), downloads in the background and offers "Restart
/// to Update". Releases are made by CI (<c>vpk pack</c> + upload); see <c>windows/README.md</c>.
/// </summary>
internal sealed class UpdateService : ObservableObject
{
    public const string RepositoryUrl = "https://github.com/srinidhibhat45/Halo";
    private static readonly TimeSpan FirstCheckDelay = TimeSpan.FromSeconds(20);
    private static readonly TimeSpan CheckInterval = TimeSpan.FromHours(24);

    private readonly UpdateManager _manager = new(new GithubSource(RepositoryUrl, null, false));
    private readonly DispatcherTimer _timer = new();
    /// <summary>The UI thread's dispatcher (download progress arrives on a worker thread).</summary>
    private readonly Dispatcher _dispatcher = Dispatcher.CurrentDispatcher;
    private UpdateInfo? _pending;
    private UpdateState _state;
    private string? _detail;
    private int _progress;

    public UpdateService()
    {
        _state = _manager.IsInstalled ? UpdateState.Idle : UpdateState.NotInstalled;
        if (_manager.IsInstalled && _manager.UpdatePendingRestart is { } downloaded)
        {
            _state = UpdateState.ReadyToRestart;
            _detail = downloaded.Version.ToString();
        }
        _timer.Tick += async (_, _) =>
        {
            _timer.Interval = CheckInterval;
            if (AutomaticChecks) await CheckAsync();
        };
    }

    /// <summary>Raised just before Halo quits to apply an update (save anything pending).</summary>
    public event Action? Restarting;

    /// <summary>Whether to check by itself (the <c>checksForUpdates</c> setting).</summary>
    public bool AutomaticChecks { get; set; } = true;

    public UpdateState State
    {
        get => _state;
        private set
        {
            if (!Set(ref _state, value)) return;
            OnPropertyChanged(nameof(Summary));
            OnPropertyChanged(nameof(CanRestartToUpdate));
        }
    }

    /// <summary>Download progress, 0–100.</summary>
    public int Progress
    {
        get => _progress;
        private set
        {
            if (Set(ref _progress, value)) OnPropertyChanged(nameof(Summary));
        }
    }

    /// <summary>The installed version (from Velopack when installed, else the assembly).</summary>
    public string CurrentVersion =>
        _manager.CurrentVersion?.ToString()
        ?? Assembly.GetExecutingAssembly().GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion.Split('+')[0]
        ?? "0.0.0";

    /// <summary>A line for About and the tray, e.g. "Version 1.2.0 is ready. Restart to update."</summary>
    public string Summary => State switch
    {
        UpdateState.NotInstalled => "Updates work in the installed app (Setup.exe).",
        UpdateState.Checking => "Checking for updates…",
        UpdateState.Downloading => $"Downloading version {_detail}… {Progress} %",
        UpdateState.UpToDate => "Halo is up to date.",
        UpdateState.ReadyToRestart => $"Version {_detail} is ready. Restart to update.",
        UpdateState.Failed => $"Couldn't check for updates: {_detail}",
        _ => "",
    };

    public bool CanRestartToUpdate => State == UpdateState.ReadyToRestart;

    /// <summary>Starts the launch-then-daily schedule.</summary>
    public void Start()
    {
        if (State == UpdateState.NotInstalled) return;
        _timer.Interval = FirstCheckDelay;
        _timer.Start();
    }

    /// <summary>Checks now and downloads any newer version in the background.</summary>
    public async Task CheckAsync()
    {
        if (State is UpdateState.NotInstalled or UpdateState.Checking or UpdateState.Downloading or UpdateState.ReadyToRestart) return;
        State = UpdateState.Checking;
        try
        {
            var update = await _manager.CheckForUpdatesAsync();
            if (update is null)
            {
                State = UpdateState.UpToDate;
                return;
            }
            _detail = update.TargetFullRelease.Version.ToString();
            Progress = 0;
            State = UpdateState.Downloading;
            await _manager.DownloadUpdatesAsync(update, p => _dispatcher.BeginInvoke(() => Progress = p));
            _pending = update;
            State = UpdateState.ReadyToRestart;
        }
        catch (Exception e) when (e is HttpRequestException or IOException or InvalidOperationException or TaskCanceledException)
        {
            Trace.TraceWarning($"Update check failed: {e}");
            _detail = e.Message;
            State = UpdateState.Failed;
        }
    }

    /// <summary>Quits, applies the downloaded update and starts the new version.</summary>
    public void RestartToUpdate()
    {
        var asset = _pending?.TargetFullRelease ?? _manager.UpdatePendingRestart;
        if (asset is null) return;
        Restarting?.Invoke();
        _manager.ApplyUpdatesAndRestart(asset);
    }
}
