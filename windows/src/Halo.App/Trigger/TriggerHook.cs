using System.Windows.Threading;
using Halo.App.Interop;
using Halo.Core;

namespace Halo.App.Trigger;

/// <summary>Keys the open ring responds to.</summary>
internal enum NavigationKind
{
    Escape, Confirm, Back, Tab, ShiftTab, Up, Down, Left, Right, Digit, Keypad,
}

/// <param name="Digit">For <see cref="NavigationKind.Digit"/> and <see cref="NavigationKind.Keypad"/>: 0–9.</param>
internal readonly record struct NavigationKey(NavigationKind Kind, int Digit = 0);

/// <summary>A key pressed while recording a new trigger.</summary>
/// <param name="Vk">The key, or 0 when only the held modifiers changed (for live display).</param>
internal readonly record struct RecordedKey(ushort Vk, Modifiers Modifiers);

/// <summary>
/// Turns raw keyboard-hook events into Halo's trigger presses and releases, the ring's navigation
/// keys and trigger-recorder input.
/// </summary>
/// <remarks>
/// <para>The filter runs on the hook thread and only reads fields the UI thread writes atomically;
/// it reports everything back to the UI dispatcher asynchronously.</para>
/// <list type="bullet">
/// <item>The trigger combo is swallowed (so it never reaches the app in front). Its press is
/// reported once; auto-repeat is latched and swallowed; the release of its key is reported.</item>
/// <item>While the ring is open, Esc, Enter, Space, Backspace, Delete, Tab, arrows and digits
/// (top row and keypad) are swallowed and reported, but only without Ctrl/Alt/Win held, and the
/// matching key-ups are swallowed too.</item>
/// <item>While recording, every non-modifier key press is swallowed and reported instead.</item>
/// </list>
/// </remarks>
internal sealed class TriggerHook : IDisposable
{
    private readonly Dispatcher _dispatcher;
    private readonly HookThread _hooks;

    // Written on the UI thread, read on the hook thread.
    private volatile KeyCombo? _trigger;
    private volatile bool _navigating;
    private volatile bool _suspended;
    private volatile Action<RecordedKey>? _recorder;

    // Hook-thread state.
    /// <summary>Modifier keys held, with when they went down.</summary>
    private readonly Dictionary<ushort, double> _heldModifierKeys = [];
    private readonly HashSet<ushort> _swallowedDowns = [];
    private bool _triggerLatched;
    private ushort _latchedVk;

    public TriggerHook(Dispatcher dispatcher, Action<MouseDownEvent> mouseDown)
    {
        _dispatcher = dispatcher;
        _hooks = new HookThread(Filter, mouseDown);
    }

    /// <summary>Raised on the UI thread with the press time (seconds, <see cref="HaloClock"/>).</summary>
    public event Action<double>? TriggerPressed;

    /// <summary>Raised on the UI thread with the release time.</summary>
    public event Action<double>? TriggerReleased;

    /// <summary>Raised on the UI thread for navigation keys while <see cref="IsNavigating"/>.</summary>
    public event Action<NavigationKey>? Navigation;

    public bool IsInstalled => _hooks.IsKeyboardHookInstalled;

    /// <summary>The combo that opens the ring; null disables the trigger.</summary>
    public KeyCombo? Trigger
    {
        get => _trigger;
        set => _trigger = value;
    }

    /// <summary>True while the trigger is down (its key-up not seen yet).</summary>
    public bool IsTriggerHeld { get; private set; }

    /// <summary>While true the trigger is ignored (Halo paused).</summary>
    public bool IsSuspended
    {
        get => _suspended;
        set => _suspended = value;
    }

    public bool IsNavigating => _navigating;

    /// <summary>Starts grabbing navigation keys and listening for outside clicks (the ring opened).</summary>
    public void BeginNavigation()
    {
        _navigating = true;
        _hooks.SetMouseHook(true);
    }

    /// <summary>Releases navigation keys and the click hook (the ring closed).</summary>
    public void EndNavigation()
    {
        _navigating = false;
        _hooks.SetMouseHook(false);
    }

    /// <summary>
    /// Records the next shortcut: every key press (and modifier change) is swallowed and reported to
    /// <paramref name="onKey"/> on the UI thread until <see cref="EndRecording"/>.
    /// </summary>
    public void BeginRecording(Action<RecordedKey> onKey) => _recorder = onKey;

    public void EndRecording() => _recorder = null;

    public void Dispose() => _hooks.Dispose();

    /// <summary>Hook-thread filter: returns true to swallow the event.</summary>
    private bool Filter(KeyEvent e)
    {
        if (e.IsOwnInjection) return false;

        var modifierFlag = VirtualKeys.ModifierFlag(e.Vk);
        if (modifierFlag != Modifiers.None)
        {
            if (!e.IsDown) _heldModifierKeys.Remove(e.Vk);
            else _heldModifierKeys.TryAdd(e.Vk, e.Time);
            if (_recorder is { } watcher) Post(() => watcher(new RecordedKey(0, HeldModifiers())));
            return false;
        }

        ForgetStaleModifiers(e.Time);
        var modifiers = HeldModifiers();

        if (_recorder is { } recorder)
        {
            if (e.IsDown)
            {
                _swallowedDowns.Add(e.Vk);
                Post(() => recorder(new RecordedKey(e.Vk, modifiers)));
                return true;
            }
            return _swallowedDowns.Remove(e.Vk);
        }

        if (HandleTrigger(e, modifiers)) return true;
        return HandleNavigation(e, modifiers);
    }

    private bool HandleTrigger(KeyEvent e, Modifiers modifiers)
    {
        if (_triggerLatched && e.Vk == _latchedVk)
        {
            if (e.IsDown) return true;   // auto-repeat
            _triggerLatched = false;
            Post(() =>
            {
                IsTriggerHeld = false;
                TriggerReleased?.Invoke(e.Time);
            });
            return true;
        }

        if (!e.IsDown || _suspended || _trigger is not { } trigger) return false;
        if (e.Vk != trigger.KeyCode || modifiers != (trigger.Modifiers & ~Modifiers.Function)) return false;

        _triggerLatched = true;
        _latchedVk = e.Vk;
        if ((trigger.Modifiers & (Modifiers.Option | Modifiers.Command)) != 0) _hooks.TapDummyKeyAfterCurrentEvent();
        Post(() =>
        {
            IsTriggerHeld = true;
            TriggerPressed?.Invoke(e.Time);
        });
        return true;
    }

    private bool HandleNavigation(KeyEvent e, Modifiers modifiers)
    {
        if (!e.IsDown) return _swallowedDowns.Remove(e.Vk);
        if (!_navigating || (modifiers & (Modifiers.Control | Modifiers.Option | Modifiers.Command)) != 0) return false;
        if (Map(e.Vk, modifiers.HasFlag(Modifiers.Shift)) is not { } key) return false;
        _swallowedDowns.Add(e.Vk);
        Post(() => Navigation?.Invoke(key));
        return true;
    }

    private static NavigationKey? Map(ushort vk, bool shift)
    {
        if (VirtualKeys.TopRowDigit(vk) is { } digit && !shift) return new NavigationKey(NavigationKind.Digit, digit);
        if (VirtualKeys.KeypadDigit(vk) is { } pad) return new NavigationKey(NavigationKind.Keypad, pad);
        return vk switch
        {
            VirtualKeys.Escape => new NavigationKey(NavigationKind.Escape),
            VirtualKeys.Return or VirtualKeys.Space => new NavigationKey(NavigationKind.Confirm),
            VirtualKeys.Back or VirtualKeys.Delete => new NavigationKey(NavigationKind.Back),
            VirtualKeys.Tab => new NavigationKey(shift ? NavigationKind.ShiftTab : NavigationKind.Tab),
            VirtualKeys.Up => new NavigationKey(NavigationKind.Up),
            VirtualKeys.Down => new NavigationKey(NavigationKind.Down),
            VirtualKeys.Left => new NavigationKey(NavigationKind.Left),
            VirtualKeys.Right => new NavigationKey(NavigationKind.Right),
            _ => null,
        };
    }

    private Modifiers HeldModifiers()
    {
        var modifiers = Modifiers.None;
        foreach (var vk in _heldModifierKeys.Keys) modifiers |= VirtualKeys.ModifierFlag(vk);
        return modifiers;
    }

    /// <summary>
    /// Drops modifiers whose release the hook never saw (e.g. released on the secure desktop while
    /// locking). Only modifiers held for over a second are checked against the key state, so a
    /// fast injected sequence (mouse software sending Ctrl+Shift+Alt+H) is never second-guessed.
    /// </summary>
    private void ForgetStaleModifiers(double now)
    {
        foreach (var (vk, since) in _heldModifierKeys.ToArray())
        {
            if (now - since > 1.0 && !Native.IsKeyDown(vk)) _heldModifierKeys.Remove(vk);
        }
    }

    private void Post(Action action) => _dispatcher.BeginInvoke(DispatcherPriority.Send, action);
}
