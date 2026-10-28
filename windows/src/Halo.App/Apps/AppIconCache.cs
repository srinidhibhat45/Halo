using System.Windows.Media;
using Halo.App.Interop;
using Halo.Core;
using Microsoft.Win32;

namespace Halo.App.Apps;

/// <summary>
/// Real app icons by app id (executable name or AppUserModelID), looked up through the shell and
/// cached for the life of the app. Call on the UI thread.
/// </summary>
internal sealed class AppIconCache(InstalledApps apps)
{
    /// <summary>Pixel size requested from the shell: crisp for a 37 px icon at 200 % and size 1.4.</summary>
    private const int IconPixels = 96;

    private readonly Dictionary<string, ImageSource?> _icons = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>The icon of the app, or null when it can't be found.</summary>
    /// <param name="pathHint">The slot's launch path (exe or .lnk), tried first.</param>
    public ImageSource? Get(string bundleId, string? pathHint = null)
    {
        var key = $"{bundleId}|{pathHint}";
        if (_icons.TryGetValue(key, out var cached)) return cached;
        var name = ParsingName(bundleId, pathHint);
        var icon = name is null ? null : ShellItems.Icon(name, IconPixels);
        _icons[key] = icon;
        return icon;
    }

    /// <summary>Icon for a picker row (an installed or running app).</summary>
    public ImageSource? Get(InstalledApp app) => Get(app.BundleId, app.LaunchPath);

    /// <summary>Loads every app icon a ring uses, so opening the ring never waits on the shell.</summary>
    public void Prefetch(Ring ring)
    {
        foreach (var slot in ring.Slots)
        {
            switch (slot.Action)
            {
                case AppAction app:
                    Get(app.Target.BundleId, app.Target.Path);
                    break;
                case FolderAction folder:
                    Prefetch(folder.Ring);
                    break;
            }
            if (slot.Icon is AppIcon icon) Get(icon.BundleId, (slot.Action as AppAction)?.Target.Path);
        }
    }

    private string? ParsingName(string bundleId, string? pathHint)
    {
        if (!string.IsNullOrWhiteSpace(pathHint))
        {
            var expanded = PathExpansion.Expand(pathHint);
            if (expanded.StartsWith("shell:", StringComparison.OrdinalIgnoreCase) || File.Exists(expanded)) return expanded;
        }
        if (bundleId.Contains('!')) return $@"shell:AppsFolder\{bundleId}";
        if (bundleId.Length == 0) return null;
        var installed = apps.Loaded.FirstOrDefault(a => string.Equals(a.BundleId, bundleId, StringComparison.OrdinalIgnoreCase));
        if (installed is not null) return installed.LaunchPath;
        return AppPath(bundleId);
    }

    /// <summary>The registered location of an executable (<c>App Paths</c>), e.g. for <c>chrome.exe</c>.</summary>
    public static string? AppPath(string exeName)
    {
        foreach (var hive in new[] { Registry.CurrentUser, Registry.LocalMachine })
        {
            using var key = hive.OpenSubKey($@"Software\Microsoft\Windows\CurrentVersion\App Paths\{exeName}");
            if (key?.GetValue(null) is string path)
            {
                var expanded = Environment.ExpandEnvironmentVariables(path.Trim('"'));
                if (File.Exists(expanded)) return expanded;
            }
        }
        var system = Path.Combine(Environment.SystemDirectory, exeName);
        if (File.Exists(system)) return system;
        var windows = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), exeName);
        return File.Exists(windows) ? windows : null;
    }
}
