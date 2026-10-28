using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Threading;
using Halo.App.Actions;
using Halo.App.Interop;
using Halo.App.Rendering;
using Halo.Core;
using Halo.Core.Catalog;
using static Halo.App.Interop.Native;

namespace Halo.App.Overlay;

/// <summary>Speaks short messages to screen readers (Narrator) through UI Automation notifications.</summary>
internal static class Announcer
{
    public static void Announce(UIElement source, string message)
    {
        var peer = UIElementAutomationPeer.FromElement(source) ?? UIElementAutomationPeer.CreatePeerForElement(source);
        peer?.RaiseNotificationEvent(AutomationNotificationKind.Other, AutomationNotificationProcessing.ImportantMostRecent, message, "Halo");
    }
}

/// <summary>
/// Small pill-shaped notices near the ring: a brief confirmation after actions with no visible
/// effect, a message ("Saved to Screenshots"), or why something failed. Never activates, never
/// takes clicks.
/// </summary>
internal sealed class ToastPresenter
{
    private readonly Window _window;
    private readonly TextBlock _glyph;
    private readonly TextBlock _text;
    private readonly Border _card;
    private readonly DispatcherTimer _timer = new();

    public ToastPresenter()
    {
        _glyph = new TextBlock { FontFamily = new FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets"), FontSize = 16, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 10, 0) };
        _text = new TextBlock { FontFamily = PaintContext.TextFont, FontSize = 13, VerticalAlignment = VerticalAlignment.Center, TextWrapping = TextWrapping.Wrap, MaxWidth = 340 };
        _card = new Border
        {
            CornerRadius = new CornerRadius(18),
            Padding = new Thickness(16, 9, 18, 9),
            Margin = new Thickness(16),
            Child = new StackPanel { Orientation = Orientation.Horizontal, Children = { _glyph, _text } },
            Effect = new DropShadowEffect { BlurRadius = 18, ShadowDepth = 3, Opacity = 0.22 },
        };
        AutomationProperties.SetLiveSetting(_text, AutomationLiveSetting.Polite);
        _window = new Window
        {
            WindowStyle = WindowStyle.None,
            AllowsTransparency = true,
            Background = Brushes.Transparent,
            ShowInTaskbar = false,
            ShowActivated = false,
            Topmost = true,
            ResizeMode = ResizeMode.NoResize,
            SizeToContent = SizeToContent.WidthAndHeight,
            Content = _card,
            Title = "Halo",
        };
        _window.SourceInitialized += (_, _) =>
        {
            var hwnd = new WindowInteropHelper(_window).Handle;
            var style = (long)GetWindowLongPtrW(hwnd, GWL_EXSTYLE) | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TRANSPARENT;
            SetWindowLongPtrW(hwnd, GWL_EXSTYLE, (nint)style);
        };
        _timer.Tick += (_, _) => Hide();
    }

    /// <summary>Shows what an action's outcome warrants (nothing for plain success).</summary>
    public void Present(ActionOutcome outcome, Slot slot, (int X, int Y) anchor, bool showConfirmations)
    {
        switch (outcome)
        {
            case ActionOutcome.Failed failed:
                Show(0xE783, failed.Message, anchor, TimeSpan.FromSeconds(3.5));
                break;
            case ActionOutcome.SuccessWithMessage message:
                Show(GlyphOf(slot), message.Message, anchor, TimeSpan.FromSeconds(1.6));
                break;
            case ActionOutcome.Success { Confirm: true } when showConfirmations:
                Show(GlyphOf(slot), slot.DisplayTitle(), anchor, TimeSpan.FromSeconds(0.9));
                break;
        }
    }

    public void Show(int glyph, string message, (int X, int Y) anchor, TimeSpan duration)
    {
        var dark = SystemAppearance.IsDark;
        _card.Background = RingPalette.Brush(dark ? Color.FromArgb(240, 44, 44, 46) : Color.FromArgb(245, 249, 249, 249));
        _card.BorderBrush = RingPalette.Brush(dark ? Color.FromArgb(40, 255, 255, 255) : Color.FromArgb(25, 0, 0, 0));
        _card.BorderThickness = new Thickness(1);
        var foreground = RingPalette.Brush(dark ? Colors.White : Color.FromRgb(0x1A, 0x1A, 0x1A));
        _glyph.Foreground = foreground;
        _text.Foreground = foreground;
        _glyph.Text = char.ConvertFromUtf32(glyph);
        _text.Text = message;

        var display = Displays.At(anchor.X, anchor.Y);
        _window.Opacity = 0;
        if (!_window.IsVisible) _window.Show();
        _window.UpdateLayout();
        var width = (int)Math.Ceiling(_window.ActualWidth * display.Scale);
        var height = (int)Math.Ceiling(_window.ActualHeight * display.Scale);
        // Just below the ring's centre, kept on the screen.
        var x = Math.Clamp(anchor.X - width / 2, display.WorkArea.Left, display.WorkArea.Right - width);
        var y = Math.Clamp(anchor.Y + (int)(70 * display.Scale), display.WorkArea.Top, display.WorkArea.Bottom - height);
        SetWindowPos(new WindowInteropHelper(_window).Handle, HWND_TOPMOST, x, y, width, height, SWP_NOACTIVATE);
        Fade(1, 0.12);
        Announcer.Announce(_text, message);
        _timer.Stop();
        _timer.Interval = duration;
        _timer.Start();
    }

    public void Hide()
    {
        _timer.Stop();
        if (!_window.IsVisible) return;
        Fade(0, 0.18, () => _window.Hide());
    }

    private void Fade(double to, double seconds, Action? completed = null)
    {
        if (!SystemAppearance.AnimationsEnabled)
        {
            _window.BeginAnimation(UIElement.OpacityProperty, null);
            _window.Opacity = to;
            completed?.Invoke();
            return;
        }
        var animation = new DoubleAnimation(to, TimeSpan.FromSeconds(seconds)) { EasingFunction = new QuadraticEase() };
        if (completed is not null) animation.Completed += (_, _) => { if (_window.Opacity <= 0.01) completed(); };
        _window.BeginAnimation(UIElement.OpacityProperty, animation);
    }

    private static int GlyphOf(Slot slot)
    {
        var symbol = slot.DisplayIcon() is SymbolIcon s ? s.Name : slot.Action?.DefaultSymbol() ?? "checkmark.seal";
        var candidates = SymbolGlyphs.Candidates(symbol);
        return candidates.Count > 0 ? candidates[^1] : 0xE73E;
    }
}
