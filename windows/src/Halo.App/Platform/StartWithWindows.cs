using Microsoft.Win32;

namespace Halo.App.Platform;

/// <summary>"Start with Windows": a per-user <c>Run</c> registry value (no admin rights needed).</summary>
internal static class StartWithWindows
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "Halo";

    /// <summary>Command-line flag Halo is started with at sign-in (no settings window).</summary>
    public const string BackgroundArgument = "--background";

    public static bool IsEnabled
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey);
            return key?.GetValue(ValueName) is string;
        }
    }

    /// <summary>Adds or removes the entry. The path is the running executable, which Velopack keeps
    /// at a stable location across updates (<c>%LocalAppData%\Halo\current\Halo.exe</c>).</summary>
    public static void Set(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RunKey, writable: true);
        if (enabled && Environment.ProcessPath is { } exe) key.SetValue(ValueName, $"\"{exe}\" {BackgroundArgument}");
        else key.DeleteValue(ValueName, throwOnMissingValue: false);
    }
}
