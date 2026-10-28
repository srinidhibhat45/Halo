using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Media;
using Halo.App.Interop;
using Halo.Core;
using Halo.Core.Interaction;

namespace Halo.App.Rendering;

/// <summary>
/// Draws a <see cref="RingViewModel"/> with the Classic or Glass painter and animates it: while
/// any spring is moving it re-renders on every composition frame (<c>CompositionTarget.Rendering</c>),
/// then stops listening so an idle ring costs nothing.
/// </summary>
/// <remarks>
/// Used by the live overlay and by the configurator (editor mode). Hit-testing is geometric
/// (<see cref="HitTest(Point)"/>); the whole canvas is mouse-transparent to WPF only where the
/// owner wants it to be.
/// </remarks>
internal sealed class RingCanvas : FrameworkElement
{
    /// <summary>Near-invisible fill so a layered overlay window receives mouse input over its whole area.</summary>
    private static readonly Brush HitSurface = RingPalette.Brush(Color.FromArgb(1, 0, 0, 0));

    private readonly RingAnimator _animator = new();
    private readonly SlotArtwork _art;
    private RingViewModel? _model;
    private RingPalette _palette = new(RingColor.FromPreset(RingColorPreset.Blue), dark: false);
    private bool _ticking;
    private TimeSpan _lastFrame;

    public RingCanvas(SlotArtwork art)
    {
        _art = art;
        Focusable = false;
        RenderOptions.SetBitmapScalingMode(this, BitmapScalingMode.HighQuality);
        AutomationProperties.SetName(this, "Halo ring");
        Unloaded += (_, _) => StopTicking();
    }

    public RingViewModel? Model
    {
        get => _model;
        set
        {
            if (_model is not null) _model.Changed -= Refresh;
            _model = value;
            if (_model is not null) _model.Changed += Refresh;
            Refresh();
        }
    }

    /// <summary>True while an animation is running.</summary>
    public bool IsAnimating => _ticking;

    /// <summary>What a point in this element (DIPs) is over, for clicks in the editor.</summary>
    public HitTarget HitTest(Point point)
    {
        if (_model is null) return HitTarget.None;
        var centre = new Point(ActualWidth / 2, ActualHeight / 2);
        return _model.Layout.HitTest(point.X - centre.X, point.Y - centre.Y, holding: false, current: _model.Highlighted);
    }

    /// <summary>Re-reads the model (call after changing it) and animates toward the new state.</summary>
    public void Refresh()
    {
        if (_model is null) return;
        _palette = new RingPalette(_model.Accent, SystemAppearance.IsDark);
        _animator.Sync(_model, HaloClock.Now, SystemAppearance.AnimationsEnabled);
        StartTicking();
        InvalidateVisual();
    }

    /// <summary>Gives the canvas a UI Automation peer so its name is exposed and Narrator announcements raised on it are heard.</summary>
    protected override AutomationPeer OnCreateAutomationPeer() => new FrameworkElementAutomationPeer(this);

    protected override void OnRender(DrawingContext dc)
    {
        dc.DrawRectangle(_model?.Mode == RingMode.Live ? HitSurface : Brushes.Transparent, null, new Rect(RenderSize));
        if (_model is null || RenderSize.Width <= 0) return;
        var context = new PaintContext(_model, _animator, _art, _palette, RenderSize, VisualTreeHelper.GetDpi(this).PixelsPerDip);
        if (_model.Theme == RingTheme.Glass) GlassPainter.Paint(dc, context);
        else ClassicPainter.Paint(dc, context);
    }

    private void StartTicking()
    {
        if (_ticking) return;
        _ticking = true;
        _lastFrame = TimeSpan.Zero;
        CompositionTarget.Rendering += OnFrame;
    }

    private void StopTicking()
    {
        if (!_ticking) return;
        _ticking = false;
        CompositionTarget.Rendering -= OnFrame;
    }

    private void OnFrame(object? sender, EventArgs e)
    {
        // Rendering can fire more than once per frame; only step once per new frame time.
        var time = e is RenderingEventArgs args ? args.RenderingTime : TimeSpan.Zero;
        if (time == _lastFrame) return;
        var dt = _lastFrame == TimeSpan.Zero ? 1.0 / 60 : Math.Clamp((time - _lastFrame).TotalSeconds, 0, 0.05);
        _lastFrame = time;
        var moving = _animator.Step(dt, HaloClock.Now);
        InvalidateVisual();
        if (!moving) StopTicking();
    }
}
