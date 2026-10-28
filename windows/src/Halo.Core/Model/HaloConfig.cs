using Halo.Core.Catalog;

namespace Halo.Core;

/// <summary>Everything the user configures. Persisted as JSON by <see cref="Storage.ConfigFile"/>.</summary>
public sealed record HaloConfig
{
    public const int CurrentSchemaVersion = 1;

    public int SchemaVersion { get; init; } = CurrentSchemaVersion;
    public AppSettings Settings { get; init; } = new();
    /// <summary>The ring used in every app without its own enabled ring ("Everywhere").</summary>
    public Ring GlobalRing { get; init; } = DefaultRings.Global();
    /// <summary>App-specific rings, in sidebar order.</summary>
    public IReadOnlyList<AppProfile> AppProfiles { get; init; } = [];

    public static HaloConfig Default => new();

    /// <summary>The ring to show while the app identified by <paramref name="appId"/> is in front.</summary>
    public ResolvedRing ResolveRing(string? appId) => ResolveRing(appId is null ? Array.Empty<string>() : new[] { appId });

    /// <summary>
    /// The ring to show while the app known by any of <paramref name="appIds"/> (its AppUserModelID,
    /// executable name…) is in front. Ids compare case-insensitively. With
    /// <see cref="AppProfile.InheritsGlobalSlots"/>, empty slots show the global ring's slot at the
    /// same position.
    /// </summary>
    public ResolvedRing ResolveRing(IReadOnlyCollection<string> appIds)
    {
        var profile = Settings.AppRingsEnabled
            ? AppProfiles.FirstOrDefault(p => p.IsEnabled && appIds.Contains(p.BundleId, StringComparer.OrdinalIgnoreCase))
            : null;
        if (profile is null) return new ResolvedRing(GlobalRing, null);

        var ring = profile.Ring;
        if (profile.InheritsGlobalSlots)
        {
            for (var i = 0; i < ring.SlotCount; i++)
            {
                if (ring[i].Action is not null || !GlobalRing.Contains(i) || GlobalRing[i].Action is null) continue;
                // Keep ids unique within the resolved ring.
                ring = ring.WithSlot(i, GlobalRing[i] with { Id = ring[i].Id });
            }
        }
        return new ResolvedRing(ring, profile);
    }

    public int? ProfileIndex(Guid id)
    {
        var index = AppProfiles.ToList().FindIndex(p => p.Id == id);
        return index >= 0 ? index : null;
    }

    public int? ProfileIndex(string bundleId)
    {
        var index = AppProfiles.ToList().FindIndex(p => string.Equals(p.BundleId, bundleId, StringComparison.OrdinalIgnoreCase));
        return index >= 0 ? index : null;
    }

    public bool Equals(HaloConfig? other) =>
        other is not null
        && SchemaVersion == other.SchemaVersion
        && Settings == other.Settings
        && GlobalRing == other.GlobalRing
        && AppProfiles.SequenceEqual(other.AppProfiles);

    public override int GetHashCode() => HashCode.Combine(SchemaVersion, Settings, GlobalRing, AppProfiles.Count);
}

/// <summary>A ring that replaces the global ring while a specific app is in front.</summary>
/// <param name="BundleId">The app's AppUserModelID or executable name (JSON key <c>bundleID</c>).</param>
/// <param name="InheritsGlobalSlots">Empty slots show the global ring's action at the same position.</param>
public sealed record AppProfile(Guid Id, string BundleId, string AppName, bool IsEnabled, Ring Ring, bool InheritsGlobalSlots)
{
    public AppProfile(string bundleId, string appName, Ring? ring = null, bool isEnabled = true, bool inheritsGlobalSlots = false)
        : this(Guid.NewGuid(), bundleId, appName, isEnabled, ring ?? new Ring(), inheritsGlobalSlots) { }
}

/// <summary>The ring chosen for the app in front, and the app profile in effect (null for the global ring).</summary>
public sealed record ResolvedRing(Ring Ring, AppProfile? Profile);
