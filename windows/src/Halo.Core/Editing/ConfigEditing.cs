using Halo.Core.Catalog;

namespace Halo.Core.Editing;

/// <summary>Which configured ring: the global ("Everywhere") ring or an app ring.</summary>
public abstract record RingTarget
{
    private RingTarget() { }

    public sealed record Global : RingTarget;

    public sealed record App(Guid ProfileId) : RingTarget;

    public static RingTarget Everywhere { get; } = new Global();
}

/// <summary>
/// A ring level in the config: a target ring plus a folder path into it (indices of folder slots,
/// from the target ring down). The empty path is the target ring itself.
/// </summary>
public sealed record RingAddress(RingTarget Target, IReadOnlyList<int> Path)
{
    public RingAddress(RingTarget target) : this(target, Array.Empty<int>()) { }

    /// <summary>The address of the folder at <paramref name="slot"/> of this level.</summary>
    public RingAddress Child(int slot) => this with { Path = [.. Path, slot] };

    /// <summary>The parent level, or null at the target ring.</summary>
    public RingAddress? Parent => Path.Count == 0 ? null : this with { Path = Path.Take(Path.Count - 1).ToArray() };

    public bool Equals(RingAddress? other) => other is not null && Target == other.Target && Path.SequenceEqual(other.Path);

    public override int GetHashCode() => HashCode.Combine(Target, Path.Count);
}

/// <summary>
/// Pure edits of a <see cref="HaloConfig"/>. Every method returns a new config (unchanged when the
/// address is no longer valid), so the app can keep the old one for undo.
/// </summary>
public static class ConfigEditing
{
    /// <summary>The ring at <paramref name="address"/>, or null if it no longer exists.</summary>
    public static Ring? RingAt(this HaloConfig config, RingAddress address)
    {
        var root = address.Target switch
        {
            RingTarget.App app => config.AppProfiles.FirstOrDefault(p => p.Id == app.ProfileId)?.Ring,
            _ => config.GlobalRing,
        };
        return root?.RingAt(address.Path);
    }

    /// <summary>Replaces the ring at <paramref name="address"/> with <paramref name="body"/>'s result.</summary>
    public static HaloConfig UpdatingRing(this HaloConfig config, RingAddress address, Func<Ring, Ring> body)
    {
        switch (address.Target)
        {
            case RingTarget.App app:
                var index = config.ProfileIndex(app.ProfileId);
                if (index is not { } i) return config;
                var profile = config.AppProfiles[i];
                var ring = profile.Ring.UpdatingRing(address.Path, body);
                return ring is null ? config : config.ReplacingProfile(i, profile with { Ring = ring });
            default:
                var global = config.GlobalRing.UpdatingRing(address.Path, body);
                return global is null ? config : config with { GlobalRing = global };
        }
    }

    /// <summary>Replaces slot <paramref name="index"/> of the ring at <paramref name="address"/>.</summary>
    public static HaloConfig SettingSlot(this HaloConfig config, RingAddress address, int index, Slot slot) =>
        config.UpdatingRing(address, ring => ring.Contains(index) ? ring.WithSlot(index, slot) : ring);

    /// <summary>
    /// Assigns <paramref name="action"/> to slot <paramref name="index"/>, keeping the slot's id and
    /// tint but resetting a custom title and icon that described the previous action.
    /// </summary>
    public static HaloConfig AssigningAction(this HaloConfig config, RingAddress address, int index, HaloAction action, string? title = null) =>
        config.UpdatingRing(address, ring => ring.Contains(index)
            ? ring.WithSlot(index, ring[index] with { Action = action, Title = title, Icon = null })
            : ring);

    /// <summary>Appends an app ring. A new ring may start as a copy of the global ring.</summary>
    public static HaloConfig AddingProfile(this HaloConfig config, AppProfile profile) =>
        config with { AppProfiles = [.. config.AppProfiles, profile] };

    public static HaloConfig RemovingProfile(this HaloConfig config, Guid id) =>
        config with { AppProfiles = config.AppProfiles.Where(p => p.Id != id).ToArray() };

    public static HaloConfig UpdatingProfile(this HaloConfig config, Guid id, Func<AppProfile, AppProfile> body) =>
        config.ProfileIndex(id) is { } i ? config.ReplacingProfile(i, body(config.AppProfiles[i])) : config;

    /// <summary>A new app ring for the app; <paramref name="copyGlobal"/> starts it from the global ring's slots (with fresh ids).</summary>
    public static AppProfile NewProfile(this HaloConfig config, string bundleId, string appName, bool copyGlobal) =>
        new(bundleId, appName, copyGlobal ? new Ring(config.GlobalRing.Slots.Select(s => s with { Id = Guid.NewGuid() })) : new Ring());

    /// <summary>The display name of a level, for breadcrumbs: "Everywhere", the app's name, then folder titles.</summary>
    public static IReadOnlyList<string> Breadcrumb(this HaloConfig config, RingAddress address)
    {
        var names = new List<string>
        {
            address.Target switch
            {
                RingTarget.App app => config.AppProfiles.FirstOrDefault(p => p.Id == app.ProfileId)?.AppName ?? "App",
                _ => "Everywhere",
            },
        };
        var ring = config.RingAt(new RingAddress(address.Target));
        foreach (var slot in address.Path)
        {
            if (ring is null || !ring.Contains(slot)) break;
            names.Add(ring[slot].DisplayTitle());
            ring = (ring[slot].Action as FolderAction)?.Ring;
        }
        return names;
    }

    private static HaloConfig ReplacingProfile(this HaloConfig config, int index, AppProfile profile)
    {
        var profiles = config.AppProfiles.ToArray();
        profiles[index] = profile;
        return config with { AppProfiles = profiles };
    }
}
