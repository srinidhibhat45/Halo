using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Media.Imaging;
using Halo.App.Interop;
using Halo.App.Overlay;
using Halo.App.Platform;
using Halo.Core;
using Halo.Core.Editing;
using Halo.Core.Storage;
using static Halo.App.Interop.Native;

namespace Halo.App;

/// <summary>
/// <c>Halo.exe --self-test &lt;folder&gt;</c> (or <c>HALO_SELF_TEST=&lt;folder&gt;</c>): starts Halo as a user would, then checks the pieces a
/// first run depends on (settings, keyboard hook, tray icon, settings window), presses the trigger
/// the way mouse software does, and saves screenshots and report.txt to the folder. Exits 0 when
/// every check passed. CI runs it against the installed copy (see .github/workflows/ci.yml).
/// </summary>
internal partial class HaloApplication
{
    private readonly List<string> _selfTestFailures = [];

    private async void RunSelfTest(string folder)
    {
        var report = new StringBuilder();
        void Check(string name, bool passed, string? detail = null)
        {
            report.AppendLine($"{(passed ? "PASS" : "FAIL")}  {name}{(detail is null ? "" : $"  ({detail})")}");
            if (!passed) _selfTestFailures.Add(name);
        }

        try
        {
            Directory.CreateDirectory(folder);
            report.AppendLine($"Halo {typeof(HaloApplication).Assembly.GetName().Version} on {Environment.OSVersion} ({RuntimeInformation.OSArchitecture})");
            report.AppendLine($"Running from {Environment.ProcessPath}");
            report.AppendLine();

            // Let the first-run settings window render and the installed-apps list load.
            await Task.Delay(TimeSpan.FromSeconds(4));
            var model = _model!;
            Check("Settings load", model.LoadOutcome is ConfigLoadOutcome.Loaded or ConfigLoadOutcome.CreatedDefault, model.LoadOutcome.GetType().Name);
            Check("Keyboard hook installed", _hook!.IsInstalled);
            Check("Tray icon shown", _tray?.IsVisible == true);
            Check("Settings window opens on first run", _settings?.IsVisible == true);
            Check("Start with Windows matches the setting", StartWithWindows.IsEnabled == model.Settings.LaunchAtLogin,
                $"setting {model.Settings.LaunchAtLogin}, registry {StartWithWindows.IsEnabled}");
            Check("Default ring has actions", model.Config.GlobalRing.Slots.Any(s => s.Action is not null));
            Capture(folder, "1-first-run.png", report);

            _settings?.Model.Navigate(new RingAddress(RingTarget.Everywhere), null);
            await Task.Delay(TimeSpan.FromSeconds(1));
            Capture(folder, "2-ring-editor.png", report);

            // The trigger, sent like mouse software sends it (injected, not tagged as Halo's own).
            var screen = Displays.At(0, 0).Bounds;
            SetCursorPos(screen.Left + screen.Width / 2, screen.Top + screen.Height / 2);
            var trigger = model.Settings.Trigger ?? KeyCombo.DefaultTrigger;
            Check("A trigger is set", model.Settings.Trigger is not null);
            PressKey(trigger);
            await Task.Delay(TimeSpan.FromMilliseconds(900));
            Check($"{trigger.DisplayString} opens the ring", _overlay!.IsShowing);
            Capture(folder, "3-ring-classic.png", report);

            PressKey(new KeyCombo(VirtualKeys.Escape, Modifiers.None, "Esc"));
            await Task.Delay(TimeSpan.FromMilliseconds(700));
            Check("Esc closes the ring", !_overlay.IsShowing);

            var theme = model.Settings.Theme;
            model.UpdateSettings("Self-Test", s => s with { Theme = RingTheme.Glass });
            _overlay.TryRing(RingTarget.Everywhere);
            await Task.Delay(TimeSpan.FromMilliseconds(900));
            Check("Glass ring opens", _overlay.IsShowing);
            Capture(folder, "4-ring-glass.png", report);
            _overlay.Dismiss();
            model.UpdateSettings("Self-Test", s => s with { Theme = theme });
            await Task.Delay(TimeSpan.FromMilliseconds(500));

            _settings?.Model.ShowAbout();
            await Task.Delay(TimeSpan.FromMilliseconds(700));
            Capture(folder, "5-about.png", report);
        }
        catch (Exception e)
        {
            Check("Self-test ran to the end", false, e.ToString());
        }

        report.AppendLine();
        report.AppendLine(_selfTestFailures.Count == 0 ? "All checks passed." : $"{_selfTestFailures.Count} check(s) failed.");
        try { File.WriteAllText(Path.Combine(folder, "report.txt"), report.ToString()); } catch (IOException) { }
        Console.Out.Write(report.ToString());
        Shutdown(_selfTestFailures.Count == 0 ? 0 : 1);
    }

    /// <summary>Saves the primary display to a PNG (a missing screenshot is noted, not a failure).</summary>
    private static void Capture(string folder, string name, StringBuilder report)
    {
        var bounds = Displays.At(0, 0).Bounds;
        if (BackdropCapture.Capture(bounds.Left, bounds.Top, bounds.Width, bounds.Height) is not { } shot)
        {
            report.AppendLine($"note  couldn't capture {name}");
            return;
        }
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(shot));
        using var file = File.Create(Path.Combine(folder, name));
        encoder.Save(file);
    }

    /// <summary>Presses and releases a combination with untagged SendInput, as other software would.</summary>
    private static unsafe void PressKey(KeyCombo combo)
    {
        var modifiers = new List<ushort>();
        if (combo.Modifiers.HasFlag(Modifiers.Command)) modifiers.Add(VirtualKeys.LWin);
        if (combo.Modifiers.HasFlag(Modifiers.Control)) modifiers.Add(VirtualKeys.LControl);
        if (combo.Modifiers.HasFlag(Modifiers.Shift)) modifiers.Add(VirtualKeys.LShift);
        if (combo.Modifiers.HasFlag(Modifiers.Option)) modifiers.Add(VirtualKeys.LMenu);

        var inputs = new List<INPUT>();
        foreach (var vk in modifiers) inputs.Add(Key(vk, up: false));
        inputs.Add(Key(combo.KeyCode, up: false));
        inputs.Add(Key(combo.KeyCode, up: true));
        for (var i = modifiers.Count - 1; i >= 0; i--) inputs.Add(Key(modifiers[i], up: true));

        var array = inputs.ToArray();
        fixed (INPUT* p = array) SendInput((uint)array.Length, p, sizeof(INPUT));

        static INPUT Key(ushort vk, bool up) => new()
        {
            type = INPUT_KEYBOARD,
            u = new INPUTUNION { ki = new KEYBDINPUT { wVk = vk, wScan = (ushort)MapVirtualKeyW(vk, MAPVK_VK_TO_VSC), dwFlags = up ? KEYEVENTF_KEYUP : 0 } },
        };
    }

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool SetCursorPos(int x, int y);
}
