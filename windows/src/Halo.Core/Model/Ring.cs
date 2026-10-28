namespace Halo.Core;

/// <summary>
/// An immutable ring of slots. Slot 0 sits at the top; the rest follow clockwise. Always holds
/// <see cref="MinSlotCount"/>…<see cref="MaxSlotCount"/> slots; empty positions hold a
/// <see cref="Slot"/> with no action. Editing methods return a new ring.
/// </summary>
public sealed class Ring : IEquatable<Ring>
{
    public const int MinSlotCount = 4;
    public const int MaxSlotCount = 12;
    public const int DefaultSlotCount = 8;

    private readonly Slot[] _slots;

    /// <summary>Builds a ring from slots, padding to the minimum, truncating to the maximum and
    /// regenerating duplicate ids.</summary>
    public Ring(IEnumerable<Slot> slots) : this(slots.ToArray(), normalize: true) { }

    /// <summary>An empty ring with <paramref name="slotCount"/> slots (clamped to the supported range).</summary>
    public Ring(int slotCount = DefaultSlotCount)
    {
        _slots = Enumerable.Range(0, Clamp(slotCount)).Select(_ => new Slot()).ToArray();
    }

    /// <param name="normalize">False only for display-only rings (<see cref="Compacted"/>), which may
    /// hold fewer than <see cref="MinSlotCount"/> slots.</param>
    private Ring(Slot[] slots, bool normalize)
    {
        _slots = normalize ? Normalize(slots.ToList()) : slots;
    }

    public IReadOnlyList<Slot> Slots => _slots;
    public int SlotCount => _slots.Length;
    public int FilledCount => _slots.Count(s => s.Action is not null);
    public bool IsEmpty => FilledCount == 0;

    public Slot this[int index] => _slots[index];

    /// <summary>Replaces slot <paramref name="index"/>.</summary>
    /// <exception cref="ArgumentOutOfRangeException">The index is not a slot of this ring.</exception>
    public Ring WithSlot(int index, Slot slot)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(index);
        ArgumentOutOfRangeException.ThrowIfGreaterThanOrEqual(index, _slots.Length);
        var copy = (Slot[])_slots.Clone();
        copy[index] = slot;
        return new Ring(copy);
    }

    /// <summary>
    /// Changes the number of slots. Growing appends empty slots; shrinking drops empty slots first
    /// (from the end), then trailing filled ones, so filled slots move as little as possible.
    /// </summary>
    public Ring Resized(int newCount)
    {
        var target = Clamp(newCount);
        var slots = _slots.ToList();
        while (slots.Count < target) slots.Add(new Slot());
        while (slots.Count > target)
        {
            var emptyIndex = slots.FindLastIndex(s => s.Action is null);
            slots.RemoveAt(emptyIndex >= 0 ? emptyIndex : slots.Count - 1);
        }
        return new Ring(slots);
    }

    /// <summary>Swaps two slots (drag one slot onto another in the editor).</summary>
    public Ring Swapped(int i, int j)
    {
        if (!Contains(i) || !Contains(j)) return this;
        var copy = (Slot[])_slots.Clone();
        (copy[i], copy[j]) = (copy[j], copy[i]);
        return new Ring(copy);
    }

    /// <summary>Moves a slot to another position, shifting the others.</summary>
    public Ring Moved(int from, int to)
    {
        if (!Contains(from) || !Contains(to) || from == to) return this;
        var slots = _slots.ToList();
        var slot = slots[from];
        slots.RemoveAt(from);
        slots.Insert(to, slot);
        return new Ring(slots);
    }

    /// <summary>Clears a slot, keeping its position.</summary>
    public Ring Cleared(int index) => Contains(index) ? WithSlot(index, new Slot()) : this;

    /// <summary>Index of a slot by id, or null.</summary>
    public int? IndexOf(Guid id)
    {
        var index = Array.FindIndex(_slots, s => s.Id == id);
        return index >= 0 ? index : null;
    }

    /// <summary>
    /// The ring at a folder path (indices of folder slots from this ring downwards), or null if the
    /// path no longer points at folders. The empty path is this ring.
    /// </summary>
    public Ring? RingAt(IReadOnlyList<int> path)
    {
        var current = this;
        foreach (var i in path)
        {
            if (!current.Contains(i) || current._slots[i].Action is not FolderAction folder) return null;
            current = folder.Ring;
        }
        return current;
    }

    /// <summary>
    /// Returns this ring with the ring at <paramref name="path"/> replaced by <paramref name="body"/>'s
    /// result, or null when the path is invalid.
    /// </summary>
    public Ring? UpdatingRing(IReadOnlyList<int> path, Func<Ring, Ring> body)
    {
        if (path.Count == 0) return body(this);
        var first = path[0];
        if (!Contains(first) || _slots[first].Action is not FolderAction folder) return null;
        var inner = folder.Ring.UpdatingRing(path.Skip(1).ToArray(), body);
        return inner is null ? null : WithSlot(first, _slots[first] with { Action = new FolderAction(inner) });
    }

    public bool Contains(int index) => index >= 0 && index < _slots.Length;

    /// <summary>
    /// The filled slots only, evenly spread, for showing the live ring without gaps (a ring with 3
    /// or 5 actions looks deliberate). A ring with no actions, or no gaps, is returned as it is.
    /// </summary>
    public CompactedRing Compacted()
    {
        var filled = Enumerable.Range(0, _slots.Length).Where(i => _slots[i].Action is not null).ToArray();
        if (filled.Length == 0 || filled.Length == _slots.Length)
        {
            return new CompactedRing(this, Enumerable.Range(0, _slots.Length).ToArray());
        }
        return new CompactedRing(new Ring(filled.Select(i => _slots[i]).ToArray(), normalize: false), filled);
    }

    public bool Equals(Ring? other) => other is not null && _slots.SequenceEqual(other._slots);

    public override bool Equals(object? obj) => obj is Ring ring && Equals(ring);

    public override int GetHashCode()
    {
        var hash = new HashCode();
        foreach (var slot in _slots) hash.Add(slot);
        return hash.ToHashCode();
    }

    public static bool operator ==(Ring? left, Ring? right) => left is null ? right is null : left.Equals(right);

    public static bool operator !=(Ring? left, Ring? right) => !(left == right);

    private static int Clamp(int count) => Math.Clamp(count, MinSlotCount, MaxSlotCount);

    private static Slot[] Normalize(List<Slot> slots)
    {
        while (slots.Count < MinSlotCount) slots.Add(new Slot());
        if (slots.Count > MaxSlotCount) slots.RemoveRange(MaxSlotCount, slots.Count - MaxSlotCount);
        // Duplicate ids would break identity in the editor; regenerate any repeats.
        var seen = new HashSet<Guid>();
        for (var i = 0; i < slots.Count; i++)
        {
            if (!seen.Add(slots[i].Id)) slots[i] = slots[i] with { Id = Guid.NewGuid() };
        }
        return slots.ToArray();
    }
}

/// <summary>A ring with its empty slots removed, and where each remaining slot came from.</summary>
/// <param name="SourceIndices">For each slot of <paramref name="Ring"/>, its index in the original ring.</param>
public sealed record CompactedRing(Ring Ring, IReadOnlyList<int> SourceIndices)
{
    public bool Equals(CompactedRing? other) => other is not null && Ring == other.Ring && SourceIndices.SequenceEqual(other.SourceIndices);

    public override int GetHashCode() => HashCode.Combine(Ring, SourceIndices.Count);
}

/// <summary>One position on a ring.</summary>
/// <param name="Title">Custom label; null uses the action's default title.</param>
/// <param name="Icon">Custom icon; null uses the action's default icon.</param>
/// <param name="Tint">Custom accent for the highlight; null uses the theme's.</param>
public sealed record Slot(Guid Id, HaloAction? Action = null, string? Title = null, IconSpec? Icon = null, RingColor? Tint = null)
{
    /// <summary>A slot with a fresh id.</summary>
    public Slot(HaloAction? action = null, string? title = null, IconSpec? icon = null, RingColor? tint = null)
        : this(Guid.NewGuid(), action, title, icon, tint) { }

    public bool IsEmpty => Action is null;
}

/// <summary>How a slot's icon is drawn.</summary>
public abstract record IconSpec
{
    private protected IconSpec() { }
}

/// <summary>
/// A symbol by its SF Symbols name (shared with the Mac app). Windows draws the matching Segoe
/// Fluent Icons glyph (see <see cref="Catalog.SymbolGlyphs"/>).
/// </summary>
public sealed record SymbolIcon(string Name) : IconSpec;

/// <summary>An application's own icon, looked up by its id (AppUserModelID or executable name).</summary>
public sealed record AppIcon(string BundleId) : IconSpec;

/// <summary>A custom image (PNG, at most 256×256), embedded so exported configs stay portable.</summary>
public sealed record ImageIcon(byte[] Png) : IconSpec
{
    public bool Equals(ImageIcon? other) => other is not null && Png.AsSpan().SequenceEqual(other.Png);

    public override int GetHashCode() => Png.Length;
}

/// <summary>A single emoji or short glyph.</summary>
public sealed record EmojiIcon(string Text) : IconSpec;

public enum RingColorPreset
{
    Blue, Indigo, Purple, Pink, Red, Orange, Yellow, Green, Mint, Teal, Cyan, Brown, Graphite,
}

/// <summary>Accent colours: a named preset or a custom sRGB colour (components 0…1).</summary>
public abstract record RingColor
{
    private protected RingColor() { }

    public static RingColor FromPreset(RingColorPreset preset) => new PresetColor(preset);

    public static RingColor FromRgb(double red, double green, double blue) => new CustomColor(red, green, blue);
}

public sealed record PresetColor(RingColorPreset Preset) : RingColor;

public sealed record CustomColor(double Red, double Green, double Blue) : RingColor;
