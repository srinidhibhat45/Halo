namespace Halo.Core.Motion;

/// <summary>
/// Every motion the ring uses, as springs at speed 1 (the Mac app's <c>RingMotion</c>), plus the
/// timings the overlay relies on. Durations scale with the user's animation speed; speed 0 means no
/// animation.
/// </summary>
/// <remarks>
/// Motion is progress-driven: the renderer animates a few numbers (appear, fan, highlight, pulse)
/// with these springs and derives all geometry from them on every frame.
/// </remarks>
public static class RingMotion
{
    /// <summary>The ring opening: ≈96 % there after 0.2 s, then a ≈1 % overshoot settles; no wobble.</summary>
    public static readonly SpringSpec Appear = new(0.34, 0.82);
    /// <summary>The ring closing, and the other slots folding away while the chosen one fires.</summary>
    public static readonly SpringSpec Dismiss = new(0.2, 1);
    /// <summary>Classic highlight: the bubble's fill and glyph colour.</summary>
    public static readonly SpringSpec ClassicHighlight = new(0.19, 1);
    /// <summary>Glass highlight: the tint and the segment's outward growth.</summary>
    public static readonly SpringSpec GlassHighlight = new(0.24, 0.8);
    /// <summary>Folder children fanning out of their folder.</summary>
    public static readonly SpringSpec FanOut = new(0.36, 0.84);
    /// <summary>Folder children folding back into their folder.</summary>
    public static readonly SpringSpec FanIn = new(0.24, 1);
    /// <summary>The root ring dimming behind a fanned-out folder, and brightening again.</summary>
    public static readonly SpringSpec Dim = new(0.3, 1);
    /// <summary>A tooltip sliding out from its bubble.</summary>
    public static readonly SpringSpec LabelIn = new(0.24, 0.9);
    /// <summary>A tooltip leaving (quicker than it came).</summary>
    public static readonly SpringSpec LabelOut = new(0.14, 1);
    /// <summary>The chosen slot's pulse settling back.</summary>
    public static readonly SpringSpec PulseBack = new(0.22, 0.72);
    /// <summary>Cross-fade used instead of movement when Windows animations are off.</summary>
    public static readonly SpringSpec CrossFade = new(0.18, 1);

    /// <summary>The hub growing in at the start of the bloom.</summary>
    public static readonly SpringSpec HubBloom = new(0.22, 0.8);
    /// <summary>Each slot travelling out from the centre to its place: a quick settle with a hint of overshoot.</summary>
    public static readonly SpringSpec SlotBloom = new(0.28, 0.72);

    /// <summary>Seconds after the hub starts that slot 0 starts blooming.</summary>
    public const double BloomLead = 0.05;
    /// <summary>Seconds between successive slots blooming, clockwise from the top.</summary>
    public const double BloomStagger = 0.03;
    /// <summary>Seconds after it starts until a blooming slot is (at least) 95 % of the way out.</summary>
    public const double BloomSettle = 0.2;
    /// <summary>Scale the ring shrinks to when dismissed without running anything.</summary>
    public const double DismissToScale = 0.45;
    /// <summary>Peak scale of the chosen slot's pulse.</summary>
    public const double PulseScale = 1.08;
    /// <summary>The root ring's opacity while a folder is fanned out over it.</summary>
    public const double DimmedOpacity = 0.55;
    /// <summary>Progress by which each rank of folder children starts later than the centre child.</summary>
    public const double FanStagger = 0.05;

    /// <summary>
    /// Hover time on a folder before it opens (tap and hold modes alike): long enough to pass over
    /// a folder on the way elsewhere, short enough to feel immediate.
    /// </summary>
    public const double FolderDwell = 0.13;

    /// <summary>
    /// When slot <paramref name="index"/> starts blooming out of the hub, in seconds after the ring
    /// opens: the hub first, then slots one after another, clockwise from the top.
    /// </summary>
    public static double BloomDelay(int index, double speed) => speed > 0 ? (BloomLead + index * BloomStagger) / speed : 0;

    /// <summary>Seconds until a ring of <paramref name="slotCount"/> has bloomed open (≈0.45 s for 8 at speed 1).</summary>
    public static double BloomDuration(int slotCount, double speed) =>
        speed > 0 ? BloomDelay(Math.Max(slotCount - 1, 0), speed) + BloomSettle / speed : 0;

    /// <summary>Seconds until the dismiss animation is visually complete at <paramref name="speed"/> (0 = instant).</summary>
    public static double DismissDuration(double speed) => speed > 0 ? 0.2 / speed : 0;

    /// <summary>Seconds the chosen slot pulses on its own before the ring dismisses.</summary>
    public static double FlashDuration(double speed, bool animationsEnabled) =>
        speed > 0 && animationsEnabled ? Math.Min(0.08 / speed, 0.16) : 0;

    /// <summary>Seconds of the rejection shake (three oscillations).</summary>
    public static double ShakeDuration(double speed) => speed > 0 ? 0.3 / speed : 0;

    /// <summary>Horizontal offset of the rejection shake at <paramref name="t"/> seconds, in units of its amplitude.</summary>
    public static double Shake(double t, double speed)
    {
        var duration = ShakeDuration(speed);
        if (duration <= 0 || t <= 0 || t >= duration) return 0;
        var progress = t / duration;
        return Math.Sin(progress * 3 * 2 * Math.PI) * (1 - progress);
    }

    /// <summary>
    /// Stagger delay (in progress units) of folder child <paramref name="index"/> of
    /// <paramref name="count"/>: by distance from the middle child, so children fan out from the
    /// centre outward.
    /// </summary>
    public static double FanDelay(int index, int count) => Math.Floor(Math.Abs(index - (count - 1) / 2.0)) * FanStagger;

    /// <summary><paramref name="progress"/> starting late: 0 until it passes <paramref name="delay"/>, then
    /// rising to reach 1 together with it.</summary>
    public static double Delayed(double progress, double delay) => delay <= 0 ? progress : Math.Max(0, (progress - delay) / (1 - delay));

    public static double Lerp(double a, double b, double t) => a + (b - a) * t;

    public static double Clamp01(double x) => Math.Clamp(x, 0, 1);
}
