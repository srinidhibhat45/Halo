using System.Diagnostics;
using Halo.App.Interop;
using Halo.Core;

namespace Halo.App.Apps;

/// <summary>An app the user can pick for an app action or an app ring.</summary>
/// <param name="BundleId">Executable name (<c>chrome.exe</c>) or AppUserModelID; what app rings match on.</param>
/// <param name="LaunchPath">What to open to launch it: a Start-menu <c>.lnk</c> or an executable.</param>
internal sealed record InstalledApp(string Name, string BundleId, string LaunchPath)
{
    public AppTarget ToTarget(AppBehavior behavior = AppBehavior.Open) => new(BundleId, Name, LaunchPath, behavior);
}

/// <summary>
/// Apps from the Start menu's shortcut folders (all users and the current user), and apps with
/// windows open right now (which also covers packaged Store apps).
/// </summary>
internal sealed class InstalledApps
{
    private static readonly string[] SkippedWords = ["uninstall", "readme", "read me", "help", "documentation", "license", "website", "release notes"];
    private Task<IReadOnlyList<InstalledApp>>? _scan;

    /// <summary>The Start-menu apps, scanned once in the background (sorted by name).</summary>
    public Task<IReadOnlyList<InstalledApp>> LoadAsync() => _scan ??= Task.Run(Scan);

    /// <summary>The scan's result if it has finished, else empty.</summary>
    public IReadOnlyList<InstalledApp> Loaded => _scan is { IsCompletedSuccessfully: true } scan ? scan.Result : [];

    /// <summary>Apps with a visible window, front first, one entry per app.</summary>
    public static IReadOnlyList<InstalledApp> Running()
    {
        var apps = new List<InstalledApp>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var hwnd in WindowTools.AppWindows())
        {
            if (WindowTools.IdentityOf(hwnd) is not { } identity || identity.ProcessId == Environment.ProcessId) continue;
            var id = identity.Aumid ?? identity.ExeName;
            if (!seen.Add(id)) continue;
            apps.Add(new InstalledApp(DisplayName(identity), id, identity.Aumid is null ? identity.ExePath ?? identity.ExeName : $@"shell:AppsFolder\{identity.Aumid}"));
        }
        return apps;
    }

    /// <summary>A friendly name for a running app: its file description, else its file name.</summary>
    public static string DisplayName(AppIdentity identity)
    {
        try
        {
            var description = identity.ExePath is null ? null : FileVersionInfo.GetVersionInfo(identity.ExePath).FileDescription;
            if (!string.IsNullOrWhiteSpace(description)) return description.Trim();
        }
        catch (FileNotFoundException)
        {
        }
        return Path.GetFileNameWithoutExtension(identity.ExeName);
    }

    private static IReadOnlyList<InstalledApp> Scan()
    {
        var roots = new[]
        {
            Environment.GetFolderPath(Environment.SpecialFolder.CommonPrograms),
            Environment.GetFolderPath(Environment.SpecialFolder.Programs),
        };
        var byTarget = new Dictionary<string, InstalledApp>(StringComparer.OrdinalIgnoreCase);
        foreach (var root in roots.Where(Directory.Exists))
        {
            IEnumerable<string> links;
            try
            {
                links = Directory.EnumerateFiles(root, "*.lnk", new EnumerationOptions { RecurseSubdirectories = true, IgnoreInaccessible = true });
            }
            catch (IOException)
            {
                continue;
            }
            foreach (var link in links)
            {
                var name = Path.GetFileNameWithoutExtension(link);
                if (SkippedWords.Any(w => name.Contains(w, StringComparison.OrdinalIgnoreCase))) continue;
                var target = ShellItems.ShortcutTarget(link);
                if (target is null || !target.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) continue;
                byTarget.TryAdd(target, new InstalledApp(name, Path.GetFileName(target), link));
            }
        }
        return byTarget.Values.OrderBy(a => a.Name, StringComparer.CurrentCultureIgnoreCase).ToArray();
    }
}
