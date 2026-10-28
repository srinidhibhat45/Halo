using System.Windows;
using Halo.App.Trigger;
using Halo.Core;

namespace Halo.App.Settings.Dialogs;

/// <summary>
/// Records a key combination for a keystroke or app-shortcut action. Keys are read through
/// Halo's keyboard hook so Windows shortcuts (Win+…) can be recorded too; Escape cancels.
/// </summary>
internal partial class ShortcutWindow : Window
{
    private readonly TriggerHook _hook;
    private KeyCombo? _combo;

    public ShortcutWindow(TriggerHook hook, string title, string message, Window? owner)
    {
        _hook = hook;
        InitializeComponent();
        Owner = owner;
        Title = title;
        Message.Text = message;
        Combo.Text = "Press the keys…";
        Closed += (_, _) => _hook.EndRecording();
        Deactivated += (_, _) => _hook.EndRecording();
        Activated += (_, _) =>
        {
            if (_combo is null) _hook.BeginRecording(OnKey);
        };
    }

    /// <summary>Shows the dialog; the recorded combination, or null when cancelled.</summary>
    public KeyCombo? Record() => ShowDialog() == true ? _combo : null;

    private void OnKey(RecordedKey key)
    {
        if (key.Vk == 0)
        {
            if (_combo is null) Combo.Text = key.Modifiers == Modifiers.None ? "Press the keys…" : string.Join("+", key.Modifiers.KeyNames()) + "+…";
            return;
        }
        if (key.Vk == VirtualKeys.Escape && key.Modifiers == Modifiers.None)
        {
            DialogResult = false;
            return;
        }
        _combo = new KeyCombo(key.Vk, key.Modifiers, KeyLabels.Label(key.Vk));
        Combo.Text = _combo.DisplayString;
        // Stop recording so Enter, Tab and the buttons work again.
        _hook.EndRecording();
        UseButton.IsEnabled = true;
        AgainButton.IsEnabled = true;
        UseButton.Focus();
    }

    private void OnRecordAgain(object sender, RoutedEventArgs e)
    {
        _combo = null;
        Combo.Text = "Press the keys…";
        UseButton.IsEnabled = false;
        AgainButton.IsEnabled = false;
        _hook.BeginRecording(OnKey);
    }

    private void OnUse(object sender, RoutedEventArgs e) => DialogResult = _combo is not null;

    private void OnCancel(object sender, RoutedEventArgs e) => DialogResult = false;
}
