using Halo.Core;
using Halo.Core.Geometry;
using Halo.Core.Motion;

namespace Halo.App.Rendering;

/// <summary>
/// The ring's motion: a handful of springs (bloom, presence, highlight per slot, fan, dim,
/// tooltip, hub, pulse) re-targeted from the view model and stepped every frame. Because a
/// re-targeted spring keeps its velocity, every motion can be interrupted and reversed smoothly,
/// and input never waits for an animation (hit-testing always uses the final layout).
/// </summary>
/// <remarks>
/// <para>Opening is a sequential bloom: the hub grows in first, then the slots travel out from the
/// centre one after another, clockwise from the top (<see cref="RingMotion.BloomDelay"/>), each
/// with a quick spring settle. The editor builds its preview the same way. Dismissing shrinks and
/// fades the whole ring.</para>
/// <para>With Windows' "Animation effects" off, nothing moves or scales: appear, dismiss, fan and
/// highlight become short cross-fades. With the speed at 0 everything snaps.</para>
/// </remarks>
internal sealed class RingAnimator
{
    private static readonly SpringSpec PulseUp = new(0.12, 0.75);

    private Spring _scale = new(1, RingMotion.Appear);
    private Spring _opacity = new(1, RingMotion.Appear);
    private Spring _fan = new(0, RingMotion.FanOut);
    private Spring _dim = new(1, RingMotion.Dim);
    private Spring _label = new(0, RingMotion.LabelIn);
    private Spring _hub = new(0, RingMotion.ClassicHighlight);
    private Spring _pulse = new(0, PulseUp);
    private Spring _hubBloom = new(1, RingMotion.HubBloom);
    private Spring[] _bloom = [];
    private (double Start, double Speed)? _blooming;
    private Spring[] _highlight = [];
    private int _levelVersion = -1;
    private bool _wasPresented;
    private int? _labelTarget;
    private Ring? _shownRing;
    private ArcGeometry? _shownArc;
    private int? _shownAnchor;
    private double _now;
    private (double At, double Speed)? _shake;

    public double Scale => _scale.Value;
    public double Opacity => Math.Clamp(_opacity.Value, 0, 1);
    /// <summary>Folder children: 0 folded into their folder … 1 fanned out.</summary>
    public double Fan => _fan.Value;
    /// <summary>Opacity of the root ring behind a fanned-out folder.</summary>
    public double Dim => _dim.Value;
    /// <summary>Tooltip progress and the slot it belongs to.</summary>
    public double Label => Math.Clamp(_label.Value, 0, 1.05);
    public int? LabelSlot { get; private set; }
    public double HubHover => Math.Clamp(_hub.Value, 0, 1);
    public double Pulse => _pulse.Value;
    /// <summary>Bloom progress of the hub (0 → 1).</summary>
    public double HubBloom => _hubBloom.Value;
    /// <summary>True when motion is allowed (not just cross-fades).</summary>
    public bool Moves { get; private set; } = true;

    /// <summary>Children folding back into their folder after the user went back to the root.</summary>
    public (Ring Ring, ArcGeometry Arc, int Anchor)? Folding { get; private set; }

    /// <summary>Bloom progress of base-ring slot <paramref name="slot"/>: 0 at the centre … 1 in place (overshoots slightly).</summary>
    public double Bloom(int slot) => slot >= 0 && slot < _bloom.Length ? _bloom[slot].Value : 1;

    public double Highlight(int slot) => slot >= 0 && slot < _highlight.Length ? Math.Clamp(_highlight[slot].Value, 0, 1.1) : 0;

    /// <summary>Horizontal shake offset (in units of its amplitude) for the rejected slot, if any.</summary>
    public double ShakeOffset => _shake is { } s ? RingMotion.Shake(_now - s.At, s.Speed) : 0;

    /// <summary>Re-targets every spring from the view model's state.</summary>
    public void Sync(RingViewModel model, double now, bool animationsEnabled)
    {
        _now = now;
        var speed = model.AnimationSpeed;
        var instant = speed <= 0;
        Moves = animationsEnabled && !instant;
        SpringSpec Spec(SpringSpec spec) => Moves ? spec.AtSpeed(speed) : RingMotion.CrossFade.AtSpeed(Math.Max(speed, 1));

        var layout = model.Layout;
        if (model.LevelVersion != _levelVersion) OnLevelChanged(model, layout, Spec);

        SyncPresence(model, Spec);
        SyncHighlights(model, Spec);

        _dim.Spec = Spec(RingMotion.Dim);
        _dim.Target = layout.IsFanned ? RingMotion.DimmedOpacity : 1;

        _hub.Spec = Spec(RingMotion.ClassicHighlight);
        _hub.Target = model.IsHubHovered ? 1 : 0;

        var firing = model.Executing is not null && model.IsPresented && Moves;
        _pulse.Spec = firing ? PulseUp.AtSpeed(speed) : RingMotion.PulseBack.AtSpeed(Math.Max(speed, 0.1));
        _pulse.Target = firing ? 1 : 0;

        _shake = model.Rejected is { } r && Moves ? (r.At, speed) : null;

        if (instant) SnapAll();
        RememberShown(model, layout);
    }

    /// <summary>Advances every spring; returns true while anything is still moving.</summary>
    public bool Step(double dt, double now)
    {
        _now = now;
        var moving = false;
        void Advance(ref Spring s)
        {
            s.Step(dt);
            moving |= !s.IsAtRest;
        }
        Advance(ref _scale);
        Advance(ref _opacity);
        Advance(ref _fan);
        Advance(ref _dim);
        Advance(ref _label);
        Advance(ref _hub);
        Advance(ref _pulse);
        Advance(ref _hubBloom);
        ReleaseBloomingSlots(now);
        for (var i = 0; i < _bloom.Length; i++) Advance(ref _bloom[i]);
        for (var i = 0; i < _highlight.Length; i++) Advance(ref _highlight[i]);
        moving |= _blooming is not null;
        if (Folding is not null && _fan.IsAtRest && _fan.Value <= 0) Folding = null;
        if (_shake is { } shake && now - shake.At < RingMotion.ShakeDuration(shake.Speed)) moving = true;
        return moving;
    }

    private void OnLevelChanged(RingViewModel model, Halo.Core.Interaction.RingLayout layout, Func<SpringSpec, SpringSpec> spec)
    {
        _levelVersion = model.LevelVersion;
        _highlight = Enumerable.Range(0, model.Current.SlotCount).Select(_ => new Spring(0, RingMotion.ClassicHighlight)).ToArray();
        _labelTarget = null;
        LabelSlot = null;
        _label.Snap(0);

        switch (model.LastLevelChange)
        {
            case LevelChange.Reset:
                Folding = null;
                _fan.Snap(0);
                _dim.Snap(1);
                _bloom = Enumerable.Range(0, model.Current.SlotCount).Select(_ => new Spring(1, RingMotion.SlotBloom)).ToArray();
                // The editor builds each ring it shows; the live ring blooms when it is presented.
                if (model.Mode == RingMode.Editor) StartBloom(model.AnimationSpeed);
                break;
            case LevelChange.Pop when !layout.IsFanned && _shownRing is not null && _shownArc is { } arc && _shownAnchor is { } anchor:
                // Back at the root: the children fold into their folder.
                Folding = (_shownRing, arc, anchor);
                _fan.Spec = spec(RingMotion.FanIn);
                _fan.Target = 0;
                break;
            default:
                // A folder opened (or a deeper one closed): its children fan out from the folder.
                Folding = null;
                _fan.Snap(0);
                _fan.Spec = spec(RingMotion.FanOut);
                _fan.Target = layout.IsFanned ? 1 : 0;
                break;
        }
    }

    /// <summary>Starts the bloom: hub first, slots released one by one in <see cref="Step"/>.</summary>
    private void StartBloom(double speed)
    {
        if (!Moves)
        {
            FinishBloom();
            return;
        }
        _hubBloom.Spec = RingMotion.HubBloom.AtSpeed(speed);
        _hubBloom.Snap(0);
        _hubBloom.Target = 1;
        for (var i = 0; i < _bloom.Length; i++)
        {
            _bloom[i].Spec = RingMotion.SlotBloom.AtSpeed(speed);
            _bloom[i].Snap(0);
        }
        _blooming = (_now, speed);
    }

    /// <summary>Sets slots moving once their stagger delay has passed.</summary>
    private void ReleaseBloomingSlots(double now)
    {
        if (_blooming is not { } bloom) return;
        var elapsed = now - bloom.Start;
        var waiting = false;
        for (var i = 0; i < _bloom.Length; i++)
        {
            if (_bloom[i].Target >= 1) continue;
            if (elapsed >= RingMotion.BloomDelay(i, bloom.Speed)) _bloom[i].Target = 1;
            else waiting = true;
        }
        if (!waiting) _blooming = null;
    }

    private void FinishBloom()
    {
        _blooming = null;
        _hubBloom.Snap(1);
        for (var i = 0; i < _bloom.Length; i++) _bloom[i].Snap(1);
    }

    private void SyncPresence(RingViewModel model, Func<SpringSpec, SpringSpec> spec)
    {
        if (model.Mode != RingMode.Live)
        {
            _scale.Snap(1);
            _opacity.Snap(1);
            return;
        }
        if (model.IsPresented)
        {
            if (!_wasPresented && _opacity.Value <= 0.01)
            {
                // Opening from nothing: bloom out of the hub (or just fade in when motion is off).
                // Reopened while still fading out, it simply grows back from where it is.
                _scale.Snap(1);
                _opacity.Snap(0);
                StartBloom(model.AnimationSpeed);
            }
            _scale.Spec = spec(RingMotion.Appear);
            _opacity.Spec = spec(RingMotion.HubBloom);
            _scale.Target = 1;
            _opacity.Target = 1;
        }
        else
        {
            _scale.Spec = spec(RingMotion.Dismiss);
            _opacity.Spec = spec(RingMotion.Dismiss);
            _scale.Target = !Moves ? 1 : model.Executing is not null ? 0.92 : RingMotion.DismissToScale;
            _opacity.Target = 0;
        }
        _wasPresented = model.IsPresented;
    }

    private void SyncHighlights(RingViewModel model, Func<SpringSpec, SpringSpec> spec)
    {
        var highlightSpec = spec(model.Theme == RingTheme.Classic ? RingMotion.ClassicHighlight : RingMotion.GlassHighlight);
        var strength = model.Mode == RingMode.Editor ? 0.6 : 1.0;
        for (var i = 0; i < _highlight.Length; i++)
        {
            _highlight[i].Spec = highlightSpec;
            _highlight[i].Target = i == model.Highlighted ? strength : 0;
        }

        if (model.Highlighted == _labelTarget) return;
        _labelTarget = model.Highlighted;
        if (model.Highlighted is { } slot)
        {
            LabelSlot = slot;
            _label.Snap(0);
            _label.Spec = spec(RingMotion.LabelIn);
            _label.Target = 1;
        }
        else
        {
            _label.Spec = spec(RingMotion.LabelOut);
            _label.Target = 0;
        }
    }

    private void SnapAll()
    {
        _scale.Snap(_scale.Target);
        _opacity.Snap(_opacity.Target);
        _fan.Snap(_fan.Target);
        _dim.Snap(_dim.Target);
        _label.Snap(_label.Target);
        _hub.Snap(_hub.Target);
        _pulse.Snap(0);
        FinishBloom();
        for (var i = 0; i < _highlight.Length; i++) _highlight[i].Snap(_highlight[i].Target);
        Folding = null;
    }

    private void RememberShown(RingViewModel model, Halo.Core.Interaction.RingLayout layout)
    {
        _shownRing = model.Current;
        _shownArc = layout.ChildArc;
        _shownAnchor = layout.RootAnchor;
    }
}
