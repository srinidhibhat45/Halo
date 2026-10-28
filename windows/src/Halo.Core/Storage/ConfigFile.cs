using System.Text.Json;
using Halo.Core.Serialization;

namespace Halo.Core.Storage;

/// <summary>How loading the config went.</summary>
public abstract record ConfigLoadOutcome
{
    private ConfigLoadOutcome() { }

    /// <summary>Loaded the saved config.</summary>
    public sealed record Loaded : ConfigLoadOutcome;

    /// <summary>No config yet: started from defaults.</summary>
    public sealed record CreatedDefault : ConfigLoadOutcome;

    /// <summary>The config could not be read; it was set aside at <paramref name="MovedTo"/> and the
    /// backup (or defaults) used.</summary>
    public sealed record RecoveredFromCorruption(string MovedTo) : ConfigLoadOutcome;

    /// <summary>The config could not be read nor moved; defaults are in use and saving is unsafe.</summary>
    public sealed record Unreadable(string Reason) : ConfigLoadOutcome;
}

public sealed record ConfigLoadResult(HaloConfig Config, ConfigLoadOutcome Outcome);

/// <summary>The file isn't a Halo configuration.</summary>
public sealed class ConfigImportException(string message, Exception inner) : Exception(message, inner);

/// <summary>
/// Reading and writing <see cref="HaloConfig"/> as JSON.
/// </summary>
/// <remarks>
/// Layout in <c>%APPDATA%\Halo\</c>:
/// <list type="bullet">
/// <item><c>config.json</c>: the live config, replaced atomically on save.</item>
/// <item><c>config.backup.json</c>: the previous version, rotated on every save that changes it.</item>
/// <item><c>config.unreadable-&lt;timestamp&gt;.json</c>: a config that failed to decode, set aside (never deleted).</item>
/// </list>
/// </remarks>
public static class ConfigFile
{
    public const string ExportExtension = "haloring";

    /// <summary><c>%APPDATA%\Halo</c>.</summary>
    public static string DefaultDirectory =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Halo");

    public static string DefaultPath => Path.Combine(DefaultDirectory, "config.json");

    public static string BackupPath(string path) => Path.Combine(Path.GetDirectoryName(path) ?? ".", "config.backup.json");

    /// <summary>Loads the config at <paramref name="path"/>, falling back to the backup or defaults
    /// (and setting a broken file aside).</summary>
    public static ConfigLoadResult Load(string? path = null)
    {
        path ??= DefaultPath;
        if (!File.Exists(path)) return new ConfigLoadResult(HaloConfig.Default, new ConfigLoadOutcome.CreatedDefault());
        try
        {
            return new ConfigLoadResult(HaloJson.Decode(File.ReadAllBytes(path)), new ConfigLoadOutcome.Loaded());
        }
        catch (Exception e) when (e is JsonException or IOException or UnauthorizedAccessException)
        {
            // Try the backup before giving up on the user's setup.
            var fallback = TryDecode(BackupPath(path)) ?? HaloConfig.Default;
            try
            {
                var aside = UnreadablePath(path);
                File.Move(path, aside);
                return new ConfigLoadResult(fallback, new ConfigLoadOutcome.RecoveredFromCorruption(aside));
            }
            catch (Exception moveError) when (moveError is IOException or UnauthorizedAccessException)
            {
                return new ConfigLoadResult(fallback, new ConfigLoadOutcome.Unreadable(moveError.Message));
            }
        }
    }

    /// <summary>Writes atomically, keeping the previous file as <c>config.backup.json</c>.</summary>
    /// <exception cref="IOException">The file could not be written.</exception>
    public static void Save(HaloConfig config, string? path = null)
    {
        path ??= DefaultPath;
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        var data = HaloJson.Encode(config);
        if (File.Exists(path))
        {
            var old = File.ReadAllBytes(path);
            if (old.AsSpan().SequenceEqual(data)) return;
            // Only rotate when the content changes, so the backup stays one real edit behind.
            File.Copy(path, BackupPath(path), overwrite: true);
        }
        var temp = path + ".tmp";
        File.WriteAllBytes(temp, data);
        File.Move(temp, path, overwrite: true);
    }

    /// <summary>Data for "Export…" (the same JSON as the live file).</summary>
    public static byte[] Export(HaloConfig config) => HaloJson.Encode(config);

    /// <summary>Parses an exported file.</summary>
    /// <exception cref="ConfigImportException">The data isn't a Halo configuration.</exception>
    public static HaloConfig Import(byte[] data)
    {
        try
        {
            return HaloJson.Decode(data);
        }
        catch (JsonException e)
        {
            throw new ConfigImportException("This file isn't a Halo configuration.", e);
        }
    }

    private static HaloConfig? TryDecode(string path)
    {
        try
        {
            return File.Exists(path) ? HaloJson.Decode(File.ReadAllBytes(path)) : null;
        }
        catch (Exception e) when (e is JsonException or IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    private static string UnreadablePath(string path)
    {
        var directory = Path.GetDirectoryName(path) ?? ".";
        var stamp = DateTime.UtcNow.ToString("yyyy-MM-dd'T'HH-mm-ss'Z'", System.Globalization.CultureInfo.InvariantCulture);
        var candidate = Path.Combine(directory, $"config.unreadable-{stamp}.json");
        for (var n = 2; File.Exists(candidate); n++)
        {
            candidate = Path.Combine(directory, $"config.unreadable-{stamp}-{n}.json");
        }
        return candidate;
    }
}
