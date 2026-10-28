using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using Halo.App.Actions;
using Halo.App.Apps;
using Halo.App.Interop;
using Halo.App.Rendering;
using Halo.App.Trigger;
using Halo.Core;
using Halo.Core.Catalog;
using Halo.Core.Editing;
using Halo.Core.Geometry;
using Halo.Core.Interaction;
using Halo.Core.Motion;
using Microsoft.Win32;
using static Halo.App.Interop.Native;

namespace Halo.App.Overlay;

/// <summary>
/// Shows the ring at the pointer, runs the input state machine, and runs chosen actions.
/// </summary>
/// <remarks>
/// <para>The ring lives in one pre-warmed <see cref="OverlayWindow"/> that never activates: the app
/// in front keeps keyboard focus, so synthesised shortcuts land there. While the ring is open the
/// controller polls the pointer every frame, has the hook grab navigation keys and watch for
/// clicks elsewhere, and lets clicks through wherever the pointer isn't over the ring.</para>
/// <para>Input goes through <see cref="RingInteraction"/> (tap / hold behaviour) and its effects
/// are applied here. Resting on a folder opens it (in tap and hold modes alike); hovering another
/// root slot while a folder is fanned out switches to it. Every way of closing releases keys,
/// polling and hooks through <see cref="ReleaseSession"/>, and a watchdog catches anything that
/// slips through.</para>
/// </remarks>
internal sealed class OverlayController : IDisposable
{
    /// <summary>Foreground changes this soon after opening are side effects of the trigger, not a switch.</summary>
    private const double ActivationGrace = 0.3;
    /// <summary>The trigger's modifiers must read as released this long before a missed key-up is assumed.</summary>
    private const double MissedReleaseDelay = 0.15;
    private const int WheelNotch = 120;

    private static OverlayController? s_instance;

    private readonly AppModel _model;
    private readonly TriggerHook _hook;
    private readonly ToastPresenter _toasts;
    private readonly AppIconCache _icons;
    private readonly Action<RingAddress, int?> _openSettings;
    private readonly RingViewModel _view;
    private readonly RingCanvas _canvas;
    private readonly OverlayWindow _window;
    private readonly RingInteraction _interaction = new();
    private readonly DispatcherTimer _watchdog = new() { Interval = TimeSpan.FromSeconds(0.5) };
    private readonly nint _foregroundHook;

    private AppSettings _settings;
    private Session? _session;
    private int _generation;
    private bool _flashing;
    private bool _polling;
    private CancellationTokenSource? _hideDelay;
    private (int X, int Y)? _lastPointer;
    private bool _holdStrokeStarted;
    private (int Slot, double Since)? _dwell;
    private MouseButton? _buttonDownInRing;
    private int _wheelAccumulator;
    private double? _modifiersReleasedSince;

    /// <summary>One showing of the ring.</summary>
    /// <param name="Center">The ring's centre in physical pixels; slot angles are measured from here.</param>
    /// <param name="PressPoint">Where the pointer was when the ring opened; strokes made while holding count from here.</param>
    /// <param name="Scale">DPI scale of the monitor the ring is on.</param>
    private sealed record Session(
        RingLevels Levels, string Title, nint Foreground, AppIdentity? FrontApp,
        (int X, int Y) Center, (int X, int Y) PressPoint, double Scale, double OpenedAt, (int X, int Y, int W, int H) Frame);

    public unsafe OverlayController(AppModel model, TriggerHook hook, ToastPresenter toasts, AppIconCache icons, SlotArtwork artwork, Action<RingAddress, int?> openSettings)
    {
        if (s_instance is not null) throw new InvalidOperationException("Only one overlay controller may exist.");
        s_instance = this;
        _model = model;
        _hook = hook;
        _toasts = toasts;
        _icons = icons;
        _openSettings = openSettings;
        _settings = model.Settings;
        _view = new RingViewModel(RingMode.Live, model.Config.GlobalRing, _settings);
        _canvas = new RingCanvas(artwork) { Model = _view };
        _window = new OverlayWindow(_canvas);

        _hook.Trigger = _settings.Trigger;
        _hook.TriggerPressed += TriggerDown;
        _hook.TriggerReleased += TriggerUp;
        _hook.Navigation += Navigate;
        _window.MouseDown += OnMouseDown;
        _window.MouseUp += OnMouseUp;
        _window.MouseWheel += OnMouseWheel;
        _watchdog.Tick += (_, _) => CheckInvariants();

        SystemEvents.SessionSwitch += OnSystemChange;
        SystemEvents.DisplaySettingsChanged += OnSystemChange;
        SystemEvents.PowerModeChanged += OnPowerModeChanged;
        _foregroundHook = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, 0, &OnForegroundEvent, 0, 0,
            WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);

        ApplyInteractionSettings();
        _window.Prewarm();
        _icons.Prefetch(model.Config.GlobalRing);
    }

    /// <summary>True while the ring is open and accepting input (until it starts to dismiss).</summary>
    public bool IsShowing => _session is not null;

    /// <summary>Re-reads settings for the trigger and for the next time the ring opens.</summary>
    public void SettingsChanged(HaloConfig config)
    {
        _settings = config.Settings;
        _hook.Trigger = _settings.Trigger;
        if (!_interaction.IsOpen) ApplyInteractionSettings();
        if (_session is null) _view.Apply(_settings);
        _icons.Prefetch(config.GlobalRing);
        foreach (var profile in config.AppProfiles) _icons.Prefetch(profile.Ring);
    }

    /// <summary>Opens a ring at the centre of the screen in tap mode (Settings › Try It), even an app ring that is switched off.</summary>
    public void TryRing(RingTarget target)
    {
        Dismiss();
        if (_flashing) return;
        var config = _model.Config;
        ResolvedRing resolved;
        if (target is RingTarget.App app && config.AppProfiles.FirstOrDefault(p => p.Id == app.ProfileId) is { } profile)
        {
            var preview = config with
            {
                Settings = config.Settings with { AppRingsEnabled = true },
                AppProfiles = config.AppProfiles.Select(p => p.Id == profile.Id ? p with { IsEnabled = true } : p).ToArray(),
            };
            resolved = preview.ResolveRing(profile.BundleId);
        }
        else
        {
            resolved = new ResolvedRing(config.GlobalRing, null);
        }
        _settings = config.Settings;
        var now = HaloClock.Now;
        var foreground = GetForegroundWindow();
        BeginSession(resolved, foreground, WindowTools.IdentityOf(foreground), centredOnScreen: true, now);
        // A press and an instant release in tap-then-click mode leave the ring open.
        _interaction.Mode = SelectionMode.TapThenClick;
        Perform(_interaction.TriggerDown(now));
        Perform(_interaction.TriggerUp(now));
        ApplyInteractionSettings();
    }

    /// <summary>Closes the ring without running anything.</summary>
    public void Dismiss()
    {
        var effects = _interaction.Cancel();   // also resets a machine left open without a session
        if (_session is null) return;
        if (effects.Count == 0) EndSession();
        else Perform(effects);
    }

    public void Dispose()
    {
        Dismiss();
        _watchdog.Stop();
        StopPolling();
        SystemEvents.SessionSwitch -= OnSystemChange;
        SystemEvents.DisplaySettingsChanged -= OnSystemChange;
        SystemEvents.PowerModeChanged -= OnPowerModeChanged;
        if (_foregroundHook != 0) UnhookWinEvent(_foregroundHook);
        _window.Close();
        s_instance = null;
    }

    // Trigger

    private void TriggerDown(double time)
    {
        if (_flashing) return;
        if (_interaction.IsOpen)
        {
            // Second press: run what is highlighted, or close.
            UpdatePointer();
            Perform(_interaction.TriggerDown(time));
            return;
        }
        if (_model.IsPaused) return;
        OpenAtPointer(time);
    }

    private void TriggerUp(double time)
    {
        _modifiersReleasedSince = null;
        if (!_interaction.IsOpen) return;
        // A flick released before the next frame still counts (mark-ahead).
        UpdatePointer();
        var wasHolding = _interaction.IsHolding;
        Perform(_interaction.TriggerUp(time));
        // Now in tap mode: the pointer points from the ring's centre, within the hub dead zone and the outer bound.
        if (wasHolding && _interaction.Phase is RingPhase.Open) UpdatePointer(force: true);
    }

    private void OpenAtPointer(double time)
    {
        var foreground = GetForegroundWindow();
        var identity = WindowTools.IdentityOf(foreground);
        var config = _model.Config;
        _settings = config.Settings;
        ApplyInteractionSettings();
        var resolved = config.ResolveRing(identity?.Ids ?? []);
        BeginSession(resolved, foreground, identity, _settings.Placement == RingPlacement.ScreenCenter, time);
        Perform(_interaction.TriggerDown(time));
    }

    private void ApplyInteractionSettings()
    {
        _interaction.Mode = _settings.SelectionMode;
        _interaction.HoldThreshold = _settings.HoldThreshold;
    }

    /// <summary>Prepares a session (placement, view model) for the Show effect to present.</summary>
    private void BeginSession(ResolvedRing resolved, nint foreground, AppIdentity? frontApp, bool centredOnScreen, double time)
    {
        var (px, py) = Displays.Cursor();
        var display = Displays.At(px, py);
        // Reopened while the last ring fades out: it stays up and grows back from where it is.
        _hideDelay?.Cancel();
        _hideDelay = null;
        _generation++;

        var target = resolved.Profile is { } profile ? new RingTarget.App(profile.Id) : RingTarget.Everywhere;
        var levels = new RingLevels(resolved.Ring, _settings.ClosesGaps, target, resolved.Profile?.Ring);
        _view.Apply(_settings);
        _view.Reset(levels);
        _view.AppBadge = resolved.Profile is { } p ? new AppBadge(p.BundleId, p.AppName, _icons.Get(p.BundleId)) : null;
        _view.IsHolding = false;

        // Keep the ring itself (plus tooltip room) on screen; the transparent canvas around it, sized
        // for fanned-out folders of the largest level, may extend past the screen edge.
        var scale = display.Scale;
        var rootMetrics = new RingMetrics(_settings.Theme, _settings.RingScale, levels.Root.SlotCount);
        var side = (int)Math.Ceiling(new RingMetrics(_settings.Theme, _settings.RingScale, RingLevels.LargestSlotCount(resolved.Ring)).CanvasSide * scale);
        var work = display.WorkArea;
        var keep = (int)Math.Ceiling((rootMetrics.ClampRadius + 8) * scale);
        var (rx, ry) = centredOnScreen ? (work.Left + work.Width / 2, work.Top + work.Height / 2) : (px, py);
        var cx = work.Width > keep * 2 ? Math.Clamp(rx, work.Left + keep, work.Right - keep) : work.Left + work.Width / 2;
        var cy = work.Height > keep * 2 ? Math.Clamp(ry, work.Top + keep, work.Bottom - keep) : work.Top + work.Height / 2;
        var frame = (cx - side / 2, cy - side / 2, side, side);

        if (_settings.Theme == RingTheme.Glass && SystemAppearance.TransparencyEnabled && !_window.IsVisible)
        {
            _view.Backdrop = BackdropCapture.Frosted(frame.Item1, frame.Item2, side, side);
        }
        else if (_settings.Theme != RingTheme.Glass)
        {
            _view.Backdrop = null;
        }

        _session = new Session(levels, resolved.Profile?.AppName ?? "Halo", foreground, frontApp, (cx, cy), (px, py), scale, time, frame);
    }

    // Effects

    private void Perform(IReadOnlyList<RingEffect> effects)
    {
        foreach (var effect in effects)
        {
            switch (effect)
            {
                case RingEffect.Show: PresentSession(); break;
                case RingEffect.Dismiss: EndSession(); break;
                case RingEffect.Highlight h: Highlight(h.Slot); break;
                case RingEffect.Execute e: Run(e.Slot); break;
                case RingEffect.EnterFolder f: EnterFolder(f.Slot); break;
                case RingEffect.ExitFolder: ExitFolder(); break;
                case RingEffect.Reject r: Reject(r.Slot); break;
            }
        }
        if (_session is not null && _view.IsHolding != _interaction.IsHolding)
        {
            _view.IsHolding = _interaction.IsHolding;
            _view.NotifyChanged();
        }
    }

    /// <summary>The Show effect: puts the prepared session on screen and starts listening.</summary>
    private void PresentSession()
    {
        if (_session is not { } session) return;
        _toasts.Hide();
        _interaction.SetLevel(RingLevels.KindsOf(session.Levels.Root));
        var (x, y, w, h) = session.Frame;
        _window.ShowAt(x, y, w, h);
        _view.IsPresented = true;
        _view.NotifyChanged();

        // The pointer drives the highlight once it moves from here; keys can take over meanwhile.
        _lastPointer = Displays.Cursor();
        _holdStrokeStarted = false;
        _dwell = null;
        _wheelAccumulator = 0;
        _buttonDownInRing = null;
        _modifiersReleasedSince = null;
        UpdateMouseRegion();
        StartPolling();
        _hook.BeginNavigation();
        _watchdog.Start();
        Announcer.Announce(_canvas, $"{session.Title} ring");
    }

    private void Highlight(int? index)
    {
        _dwell = null;
        _wheelAccumulator = 0;
        if (_view.Highlighted == index) return;
        _view.Highlighted = index;
        _view.NotifyChanged();
        if (index is { } i && _session?.Levels.SlotAt(i) is { } slot) Announcer.Announce(_canvas, slot.IsEmpty ? "Empty" : slot.DisplayTitle());
    }

    private void EnterFolder(int index)
    {
        if (_session is not { } session || session.Levels.EnterFolder(index) is null)
        {
            Dismiss();
            return;
        }
        ShowLevel(LevelChange.Push);
        Announcer.Announce(_canvas, session.Levels.Breadcrumb.LastOrDefault() ?? "Folder");
    }

    private void ExitFolder()
    {
        if (_session is not { } session || session.Levels.ExitFolder() is null) return;
        ShowLevel(LevelChange.Pop);
        Announcer.Announce(_canvas, session.Levels.Breadcrumb.LastOrDefault() ?? $"{session.Title} ring");
    }

    private void ShowLevel(LevelChange change)
    {
        if (_session is not { } session) return;
        _view.LevelChanged(change);
        _view.NotifyChanged();
        _interaction.SetLevel(RingLevels.KindsOf(session.Levels.Current));
        _dwell = null;
        // The new level highlights from the pointer only once it moves: releasing right after a
        // dwell-open must not run whatever happens to lie in that direction.
        _lastPointer = Displays.Cursor();
    }

    private void Reject(int index)
    {
        _view.Reject(index, HaloClock.Now);
        _view.NotifyChanged();
        Announcer.Announce(_canvas, "Empty slot");
    }

    /// <summary>The Execute effect: flash the slot, dismiss, then run the action.</summary>
    private async void Run(int index)
    {
        if (ReleaseSession() is not { } ended) return;
        if (ended.Levels.SlotAt(index) is not { Action: { } action } slot || action.IsFolder)
        {
            HideWindow();
            return;
        }
        _view.Executing = index;
        _view.NotifyChanged();
        _flashing = true;
        var flash = RingMotion.FlashDuration(_settings.AnimationSpeed, SystemAppearance.AnimationsEnabled);
        var token = _generation;
        if (flash > 0) await Task.Delay(TimeSpan.FromSeconds(flash));
        _flashing = false;
        if (_generation == token) HideWindow();
        if (CapturesScreen(action)) await WaitUntilHiddenAsync();

        var context = new ActionContext(ended.Foreground, ended.FrontApp, slot.DisplayTitle(), ended.Center, _settings.Trigger, _window.Handle);
        var outcome = await ActionRunner.RunAsync(action, context);
        _toasts.Present(outcome, slot, ended.Center, _settings.ShowConfirmations);
    }

    /// <summary>Screenshots (directly or in a Smart Action) must not capture the fading ring. The
    /// area snip and Snipping Tool capture later, once the user acts.</summary>
    private static bool CapturesScreen(HaloAction action) => action switch
    {
        ScreenshotAction s => s.Options.Mode is ScreenshotMode.Window or ScreenshotMode.FullScreen,
        MacroAction m => m.Macro.Steps.Any(step => CapturesScreen(step.Action)),
        _ => false,
    };

    private async Task WaitUntilHiddenAsync()
    {
        var deadline = Environment.TickCount64 + (long)((RingMotion.DismissDuration(_settings.AnimationSpeed) + 0.5) * 1000);
        while (_window.IsVisible && Environment.TickCount64 < deadline) await Task.Delay(10);
        // A moment for DWM to drop the window from the screen.
        await Task.Delay(40);
    }

    // Closing

    /// <summary>The Dismiss effect.</summary>
    private void EndSession()
    {
        if (ReleaseSession() is null) return;
        HideWindow();
    }

    /// <summary>
    /// Ends the session's input: navigation keys, pointer polling and the click hook; clicks pass
    /// through the window from now on. Returns the session that ended, or null if none was open
    /// (so nothing runs twice).
    /// </summary>
    private Session? ReleaseSession()
    {
        _hook.EndNavigation();
        StopPolling();
        _window.ClickThrough = true;
        _holdStrokeStarted = false;
        _dwell = null;
        _lastPointer = null;
        _buttonDownInRing = null;
        _modifiersReleasedSince = null;
        if (_view.IsHolding)
        {
            _view.IsHolding = false;
            _view.NotifyChanged();
        }
        var ended = _session;
        _session = null;
        return ended;
    }

    /// <summary>Plays the dismiss animation, then hides the window.</summary>
    private async void HideWindow()
    {
        _view.IsPresented = false;
        _view.NotifyChanged();
        _hideDelay?.Cancel();
        var delay = new CancellationTokenSource();
        _hideDelay = delay;
        var token = _generation;
        try
        {
            var seconds = RingMotion.DismissDuration(_settings.AnimationSpeed);
            if (seconds > 0 && SystemAppearance.AnimationsEnabled) await Task.Delay(TimeSpan.FromSeconds(seconds), delay.Token);
            else if (seconds > 0) await Task.Delay(TimeSpan.FromSeconds(RingMotion.CrossFade.Response), delay.Token);
            if (_generation == token && _session is null) _window.Hide();
        }
        catch (TaskCanceledException)
        {
            // The ring reopened while fading out.
        }
        finally
        {
            if (ReferenceEquals(_hideDelay, delay)) _hideDelay = null;
            delay.Dispose();
        }
    }

    // Pointer

    private void StartPolling()
    {
        if (_polling) return;
        _polling = true;
        CompositionTarget.Rendering += OnFrame;
    }

    private void StopPolling()
    {
        if (!_polling) return;
        _polling = false;
        CompositionTarget.Rendering -= OnFrame;
    }

    private void OnFrame(object? sender, EventArgs e)
    {
        if (_session is null)
        {
            StopPolling();
            return;
        }
        UpdatePointer();
        UpdateMouseRegion();
        CheckDwell();
        CheckMissedRelease();
    }

    /// <summary>Offset of a physical screen point from <paramref name="origin"/>, in DIPs (y-down).</summary>
    private static (double Dx, double Dy) Offset((int X, int Y) point, (int X, int Y) origin, double scale) =>
        ((point.X - origin.X) / scale, (point.Y - origin.Y) / scale);

    /// <summary>
    /// Feeds what the pointer is over to the state machine when it has moved (or when
    /// <paramref name="force"/>d), so a highlight set from the keyboard sticks until the mouse moves.
    /// </summary>
    private void UpdatePointer(bool force = false)
    {
        if (_session is not { } session || !_interaction.IsOpen) return;
        var pointer = Displays.Cursor();
        if (!force && _lastPointer is { } last && Math.Abs(pointer.X - last.X) + Math.Abs(pointer.Y - last.Y) < 1) return;
        _lastPointer = pointer;
        // In tap mode the pointer picks what is drawn under it, measured from the ring's centre.
        // While holding, strokes count from where the trigger went down, and only once the pointer
        // has left the dead zone there: a jitter during a quick tap must not pick the slot it
        // happens to face. The hold target is unbounded (a flick past the ring still counts).
        var holding = _interaction.IsHolding;
        var origin = holding ? session.PressPoint : session.Center;
        var (dx, dy) = Offset(pointer, origin, session.Scale);
        var layout = _view.Layout;
        if (holding && !_holdStrokeStarted)
        {
            if (Math.Sqrt(dx * dx + dy * dy) < layout.Metrics.HoldDeadZone) return;
            _holdStrokeStarted = true;
        }
        var hit = layout.HitTest(dx, dy, holding, _interaction.Highlighted);
        var overHub = hit is HitTarget.Hub;
        if (_view.IsHubHovered != overHub)
        {
            _view.IsHubHovered = overHub;
            _view.NotifyChanged();
        }
        switch (hit)
        {
            case HitTarget.SlotHit s: Perform(_interaction.PointerMoved(s.Index)); break;
            case HitTarget.RootSlot r: HoverRootSlot(r.Index); break;
            default: Perform(_interaction.PointerMoved(null)); break;
        }
        // A folder only opens once the pointer has moved onto it, not because it lay under a
        // resting pointer when the ring opened or the trigger came up.
        if (!force) StartDwell();
    }

    /// <summary>
    /// The pointer is over the dimmed root ring while a folder is fanned out. Over the open
    /// folder's own slot the folder stays open; over any other root slot the folder closes and that
    /// slot highlights, like moving along a menu bar (a folder there opens in turn after the dwell).
    /// </summary>
    private void HoverRootSlot(int rootIndex)
    {
        if (_session?.Levels.RootAnchor == rootIndex)
        {
            Perform(_interaction.PointerMoved(null));
            return;
        }
        ReturnToRoot();
        if (_interaction.IsOpen) Perform(_interaction.PointerMoved(rootIndex));
    }

    private void ReturnToRoot()
    {
        while (_interaction.Depth > 0 && _interaction.IsOpen) Perform(_interaction.Back());
    }

    /// <summary>Starts timing the highlighted slot if it is a folder the pointer just moved onto.</summary>
    private void StartDwell()
    {
        if (_interaction.Highlighted is not { } index || _dwell?.Slot == index) return;
        if (_session?.Levels.SlotAt(index)?.Action is not FolderAction) return;
        _dwell = (index, HaloClock.Now);
    }

    /// <summary>Opens the folder the pointer has rested on for <see cref="RingMotion.FolderDwell"/>, in tap and hold modes alike.</summary>
    private void CheckDwell()
    {
        if (_dwell is not { } dwell) return;
        if (_interaction.Highlighted != dwell.Slot)
        {
            _dwell = null;
            return;
        }
        if (HaloClock.Now - dwell.Since < RingMotion.FolderDwell) return;
        _dwell = null;
        Perform(_interaction.Dwell(dwell.Slot));
    }

    /// <summary>
    /// Fallback for a missed key-up (the hook can miss events, e.g. around the secure desktop):
    /// while holding, if the trigger's modifiers have read as released for a moment, release.
    /// </summary>
    private void CheckMissedRelease()
    {
        if (!_interaction.IsHolding || _settings.Trigger is not { } trigger) return;
        var modifiers = trigger.Modifiers & ~Modifiers.Function;
        if (modifiers == Modifiers.None) return;
        if (KeySender.HeldModifiers(modifiers) != Modifiers.None)
        {
            _modifiersReleasedSince = null;
            return;
        }
        var now = HaloClock.Now;
        _modifiersReleasedSince ??= now;
        if (now - _modifiersReleasedSince.Value > MissedReleaseDelay) TriggerUp(now);
    }

    /// <summary>
    /// The window takes the mouse only while the pointer is over something a click there would hit
    /// (or while a button that went down there is held); elsewhere clicks reach the app below and
    /// the click hook closes the ring.
    /// </summary>
    private void UpdateMouseRegion()
    {
        if (_session is not { } session) return;
        var (dx, dy) = Offset(Displays.Cursor(), session.Center, session.Scale);
        var hit = _view.Layout.HitTest(dx, dy, holding: false, current: null);
        _window.ClickThrough = hit is HitTarget.Nothing && _buttonDownInRing is null;
    }

    // Mouse

    private void OnMouseDown(object sender, MouseButtonEventArgs e)
    {
        e.Handled = true;
        if (e.ChangedButton is MouseButton.Left or MouseButton.Right) _buttonDownInRing = e.ChangedButton;
    }

    private void OnMouseUp(object sender, MouseButtonEventArgs e)
    {
        e.Handled = true;
        var down = _buttonDownInRing;
        _buttonDownInRing = null;
        if (down != e.ChangedButton) return;
        if (e.ChangedButton == MouseButton.Left) Click(Displays.Cursor(), Keyboard.Modifiers);
        else if (e.ChangedButton == MouseButton.Right) Dismiss();   // right-click inside the ring closes it
    }

    /// <summary>Clicks are decided by geometry, from the physical pointer position.</summary>
    private void Click((int X, int Y) point, ModifierKeys modifiers)
    {
        if (_session is not { } session) return;
        var (dx, dy) = Offset(point, session.Center, session.Scale);
        var hit = _view.Layout.HitTest(dx, dy, holding: false, current: _interaction.Highlighted);
        if (hit is HitTarget.RootSlot root)
        {
            ClickRootSlot(root.Index);
            return;
        }
        int? slot = hit is HitTarget.SlotHit s ? s.Index : null;
        var inHub = hit is HitTarget.Hub;
        if (IsEditClick(modifiers) && (slot is not null || inHub))
        {
            // Ctrl+click: open Halo Settings at this slot (or this level, from the hub).
            var (address, configured) = session.Levels.EditDestination(slot);
            Dismiss();
            _openSettings(address, configured);
            return;
        }
        Perform(_interaction.Click(slot, inHub));
    }

    /// <summary>A click on the dimmed root ring while a folder is fanned out: the open folder's own
    /// slot keeps it open; any other root slot closes the folder(s) and is chosen.</summary>
    private void ClickRootSlot(int rootIndex)
    {
        if (_session?.Levels.RootAnchor == rootIndex) return;
        ReturnToRoot();
        if (_interaction.IsOpen) Perform(_interaction.Click(rootIndex));
    }

    /// <summary>Ctrl+click, unless Ctrl is only down because it is part of a trigger still held.</summary>
    private bool IsEditClick(ModifierKeys modifiers)
    {
        if (!modifiers.HasFlag(ModifierKeys.Control)) return false;
        return !(_hook.IsTriggerHeld && _settings.Trigger is { } trigger && trigger.Modifiers.HasFlag(Modifiers.Control));
    }

    /// <summary>Scrolling over the ring while a volume or brightness slot is highlighted adjusts it, a step per notch.</summary>
    private async void OnMouseWheel(object sender, MouseWheelEventArgs e)
    {
        e.Handled = true;
        if (_session is not { } session || _interaction.Highlighted is not { } index) return;
        if (session.Levels.SlotAt(index) is not { Action: MediaAction media } slot || !media.Command.IsAdjustable()) return;
        _wheelAccumulator += e.Delta;
        var steps = _wheelAccumulator / WheelNotch;
        if (steps == 0) return;
        _wheelAccumulator -= steps * WheelNotch;
        var step = new MediaAction(media.Command.Adjusted(up: steps > 0) ?? media.Command);
        var context = new ActionContext(session.Foreground, session.FrontApp, slot.DisplayTitle(), session.Center, _settings.Trigger, _window.Handle);
        for (var i = 0; i < Math.Min(Math.Abs(steps), 4); i++)
        {
            var outcome = await ActionRunner.RunAsync(step, context);
            if (outcome is not ActionOutcome.Failed) continue;
            _toasts.Present(outcome, slot, session.Center, _settings.ShowConfirmations);
            return;
        }
    }

    /// <summary>A button went down anywhere (from the hook): outside the ring, close it. The click still reaches its target.</summary>
    public void OutsideClick(int x, int y)
    {
        if (_session is not { } session) return;
        var (dx, dy) = Offset((x, y), session.Center, session.Scale);
        if (_view.Layout.HitTest(dx, dy, holding: false, current: null) is HitTarget.Nothing) Dismiss();
    }

    // Keys

    private void Navigate(NavigationKey key)
    {
        if (_session is null) return;
        var layout = _view.Layout;
        switch (key.Kind)
        {
            case NavigationKind.Escape: Perform(_interaction.Escape()); break;
            case NavigationKind.Back: Perform(_interaction.Back()); break;
            case NavigationKind.Confirm: Perform(_interaction.Confirm()); break;
            case NavigationKind.Digit: Perform(_interaction.Number(key.Digit)); break;
            case NavigationKind.Tab: MoveHighlight(layout.CycledSlot(_interaction.Highlighted, clockwise: true)); break;
            case NavigationKind.ShiftTab: MoveHighlight(layout.CycledSlot(_interaction.Highlighted, clockwise: false)); break;
            case NavigationKind.Up: MoveHighlight(layout.SlotFrom(_interaction.Highlighted, Direction.Up)); break;
            case NavigationKind.Down: MoveHighlight(layout.SlotFrom(_interaction.Highlighted, Direction.Down)); break;
            case NavigationKind.Left: MoveHighlight(layout.SlotFrom(_interaction.Highlighted, Direction.Left)); break;
            case NavigationKind.Right: MoveHighlight(layout.SlotFrom(_interaction.Highlighted, Direction.Right)); break;
            case NavigationKind.Keypad when key.Digit == 5: Perform(_interaction.Confirm()); break;
            case NavigationKind.Keypad when key.Digit == 0: Perform(_interaction.Escape()); break;
            case NavigationKind.Keypad:
                if (DirectionExtensions.FromKeypadDigit(key.Digit) is { } direction) MoveHighlight(layout.SlotToward(direction));
                break;
        }
    }

    private void MoveHighlight(int slot)
    {
        // The pointer takes over again once it moves.
        _lastPointer = Displays.Cursor();
        Perform(_interaction.SetHighlight(slot));
    }

    // System events

    /// <summary>Closes the ring when the world changes under it: lock, user switch, display change.</summary>
    private void OnSystemChange(object? sender, EventArgs e) =>
        _window.Dispatcher.BeginInvoke(Dismiss);

    private void OnPowerModeChanged(object? sender, PowerModeChangedEventArgs e)
    {
        if (e.Mode == PowerModes.Suspend) _window.Dispatcher.BeginInvoke(Dismiss);
    }

    [UnmanagedCallersOnly]
    private static void OnForegroundEvent(nint hook, uint eventType, nint hwnd, int idObject, int idChild, uint thread, uint time) =>
        s_instance?.ForegroundChanged(hwnd);

    /// <summary>Another app came to the front (Alt+Tab, a notification click…): close the ring.</summary>
    private void ForegroundChanged(nint hwnd)
    {
        if (_session is not { } session || hwnd == session.Foreground || hwnd == _window.Handle) return;
        if (HaloClock.Now - session.OpenedAt <= ActivationGrace) return;
        Dismiss();
    }

    // Watchdog

    /// <summary>While the ring is up (or on its way out), checks that keys, polling and hooks exist
    /// only while a session is open, and that the window is hidden otherwise.</summary>
    private void CheckInvariants()
    {
        if (_session is not null)
        {
            if (!_window.IsVisible)
            {
                Trace.TraceWarning("Watchdog: ring window hidden while open; closing");
                Dismiss();
            }
            return;
        }
        if (_hook.IsNavigating)
        {
            Trace.TraceWarning("Watchdog: navigation keys outlived the ring; releasing");
            _hook.EndNavigation();
        }
        StopPolling();
        if (_hideDelay is not null || _flashing) return;   // still dismissing
        if (_window.IsVisible)
        {
            Trace.TraceWarning("Watchdog: ring window left on screen; hiding");
            _view.IsPresented = false;
            _view.NotifyChanged();
            _window.Hide();
        }
        _watchdog.Stop();
    }
}
