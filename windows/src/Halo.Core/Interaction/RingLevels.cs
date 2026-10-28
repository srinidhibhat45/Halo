using Halo.Core.Catalog;
using Halo.Core.Editing;

namespace Halo.Core.Interaction;

/// <summary>
/// The levels of one showing of the ring: the root ring resolved when it opened (edits made
/// meanwhile apply next time) and the folders entered since.
/// </summary>
/// <remarks>
/// With <see cref="ClosesGaps"/>, every level shows only its filled slots, evenly spread; indices
/// used here (and by the state machine and renderer) are display indices, mapped back to
/// configured positions for editing (<see cref="EditDestination"/>).
/// </remarks>
public sealed class RingLevels
{
    private readonly List<FolderLevel> _stack = [];
    private readonly IReadOnlyList<int> _rootSources;

    /// <param name="resolvedRoot">The ring to show (global or app ring, inherited slots filled in).</param>
    /// <param name="target">Which configured ring it came from (for editing).</param>
    /// <param name="profileRing">For an app ring: the profile's own ring before inheritance, to tell inherited slots apart.</param>
    public RingLevels(Ring resolvedRoot, bool closesGaps = false, RingTarget? target = null, Ring? profileRing = null)
    {
        ResolvedRoot = resolvedRoot;
        ClosesGaps = closesGaps;
        Target = target ?? RingTarget.Everywhere;
        ProfileRing = profileRing;
        var shown = Display(resolvedRoot);
        Root = shown.Ring;
        _rootSources = shown.SourceIndices;
    }

    /// <summary>A nested ring entered from a folder slot.</summary>
    /// <param name="IndexInParent">Display index of the folder slot in the level below.</param>
    /// <param name="SourceIndices">For each displayed slot, its index in the configured folder ring.</param>
    public sealed record FolderLevel(Ring Ring, string Title, int IndexInParent, IReadOnlyList<int> SourceIndices);

    /// <summary>The root ring as shown (gaps closed when <see cref="ClosesGaps"/>).</summary>
    public Ring Root { get; }

    /// <summary>The root ring as configured and resolved, before gaps were closed.</summary>
    public Ring ResolvedRoot { get; }

    public bool ClosesGaps { get; }
    public RingTarget Target { get; }
    public Ring? ProfileRing { get; }

    /// <summary>The level currently shown.</summary>
    public Ring Current => _stack.Count > 0 ? _stack[^1].Ring : Root;

    /// <summary>Folders entered, oldest first (empty at the root).</summary>
    public IReadOnlyList<FolderLevel> Stack => _stack;

    public int Depth => _stack.Count;

    /// <summary>Titles of the folders entered, root first.</summary>
    public IReadOnlyList<string> Breadcrumb => _stack.Select(l => l.Title).ToArray();

    /// <summary>The root slot (display index) the open folder(s) hang from, or null at the root.</summary>
    public int? RootAnchor => _stack.Count > 0 ? _stack[0].IndexInParent : null;

    public Slot? SlotAt(int index) => Current.Contains(index) ? Current[index] : null;

    /// <summary>Enters the folder at <paramref name="index"/> of the current level; null if that slot isn't a folder.</summary>
    public Ring? EnterFolder(int index)
    {
        if (SlotAt(index) is not { Action: FolderAction folder } slot) return null;
        var shown = Display(folder.Ring);
        _stack.Add(new FolderLevel(shown.Ring, slot.DisplayTitle(), index, shown.SourceIndices));
        return shown.Ring;
    }

    /// <summary>Returns to the parent level: the parent ring and the folder slot we came out of.</summary>
    public (Ring Ring, int FolderSlot)? ExitFolder()
    {
        if (_stack.Count == 0) return null;
        var left = _stack[^1];
        _stack.RemoveAt(_stack.Count - 1);
        return (Current, left.IndexInParent);
    }

    /// <summary>
    /// Where Ctrl-click opens the configurator: the configured ring level shown now, with the
    /// configured position of <paramref name="displaySlot"/> selected. Slots an app ring inherits
    /// from the global ring (and folders inside them) are edited in the global ring.
    /// </summary>
    public (RingAddress Address, int? Slot) EditDestination(int? displaySlot)
    {
        var sources = _rootSources;
        var path = new List<int>();
        foreach (var level in _stack)
        {
            path.Add(Map(sources, level.IndexInParent));
            sources = level.SourceIndices;
        }
        int? slot = displaySlot is { } d ? Map(sources, d) : null;
        var target = Target;
        var rootIndex = path.Count > 0 ? path[0] : slot;
        if (ProfileRing is { } profileRing && rootIndex is { } r && profileRing.Contains(r) && ResolvedRoot.Contains(r)
            && profileRing[r].Action is null && ResolvedRoot[r].Action is not null)
        {
            target = RingTarget.Everywhere;
        }
        return (new RingAddress(target, path), slot);
    }

    /// <summary>What each slot of <paramref name="ring"/> holds, for <see cref="RingInteraction.SetLevel"/>.</summary>
    public static IReadOnlyList<SlotKind> KindsOf(Ring ring) =>
        ring.Slots.Select(s => s.Action switch
        {
            null => SlotKind.Empty,
            FolderAction => SlotKind.Folder,
            _ => SlotKind.Action,
        }).ToArray();

    /// <summary>The most slots on any level of <paramref name="ring"/>, so the overlay window fits every level.</summary>
    public static int LargestSlotCount(Ring ring) =>
        ring.Slots.Aggregate(ring.SlotCount, (largest, slot) =>
            slot.Action is FolderAction folder ? Math.Max(largest, LargestSlotCount(folder.Ring)) : largest);

    private CompactedRing Display(Ring ring) =>
        ClosesGaps ? ring.Compacted() : new CompactedRing(ring, Enumerable.Range(0, ring.SlotCount).ToArray());

    private static int Map(IReadOnlyList<int> sources, int displayIndex) =>
        displayIndex >= 0 && displayIndex < sources.Count ? sources[displayIndex] : displayIndex;
}
