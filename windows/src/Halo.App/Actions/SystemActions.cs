using System.ComponentModel;
using System.Management;
using Halo.App.Interop;
using Halo.Core;
using Microsoft.Win32;
using static Halo.App.Interop.Native;

namespace Halo.App.Actions;

/// <summary>Keystrokes, media keys, brightness and Windows system commands.</summary>
internal static class SystemActions
{
    private const string PersonalizeKey = @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";
    private const uint SMTO_ABORTIFHUNG = 0x2;

    /// <summary>Sends a key combination to the app in front, once the trigger's modifiers are up.</summary>
    public static async Task<ActionOutcome> SendKeysAsync(KeyCombo combo, ActionContext context, bool confirm)
    {
        await context.ReleaseTriggerModifiersAsync();
        KeySender.Send(combo);
        return new ActionOutcome.Success(confirm);
    }

    public static async Task<ActionOutcome> MediaAsync(MediaCommand command, ActionContext context)
    {
        switch (command)
        {
            case MediaCommand.BrightnessUp or MediaCommand.BrightnessDown:
                return await Task.Run(() => AdjustBrightness(command == MediaCommand.BrightnessUp));
            default:
                await context.ReleaseTriggerModifiersAsync();
                KeySender.Tap(command switch
                {
                    MediaCommand.PlayPause => VirtualKeys.MediaPlayPause,
                    MediaCommand.NextTrack => VirtualKeys.MediaNextTrack,
                    MediaCommand.PreviousTrack => VirtualKeys.MediaPrevTrack,
                    MediaCommand.VolumeUp => VirtualKeys.VolumeUp,
                    MediaCommand.VolumeDown => VirtualKeys.VolumeDown,
                    _ => VirtualKeys.VolumeMute,
                });
                // Volume keys show Windows' own flyout; play/pause and mute have no visible effect.
                return command is MediaCommand.VolumeUp or MediaCommand.VolumeDown ? ActionOutcome.Done : ActionOutcome.Confirmed;
        }
    }

    public static async Task<ActionOutcome> RunAsync(SystemCommand command, ActionContext context)
    {
        switch (command)
        {
            case SystemCommand.LockScreen:
                return LockWorkStation() ? ActionOutcome.Done : new ActionOutcome.Failed("Windows didn't lock the PC.");
            case SystemCommand.SleepDisplay:
                // Wait for the click or key release that chose this, or the display wakes right up.
                await Task.Delay(500);
                SendMessageW(context.OverlayWindow, WM_SYSCOMMAND, SC_MONITORPOWER, 2);
                return ActionOutcome.Done;
            case SystemCommand.ScreenSaver:
                await Task.Delay(300);
                SendMessageW(context.OverlayWindow, WM_SYSCOMMAND, SC_SCREENSAVE, 0);
                return ActionOutcome.Done;
            case SystemCommand.Sleep:
                await Task.Delay(300);
                return SetSuspendState(false, false, false) ? ActionOutcome.Done : new ActionOutcome.Failed("Windows didn't go to sleep.");
            case SystemCommand.ToggleDarkMode:
                return await ToggleDarkModeAsync();
            case SystemCommand.SystemSettings:
                return Open("ms-settings:");
            case SystemCommand.Siri:
                return Open("ms-copilot:", "Copilot isn't installed.");
            case SystemCommand.DoNotDisturb:
                return new ActionOutcome.Failed("Windows doesn't let apps switch Do Not Disturb.");
            case SystemCommand.Launchpad:
                await context.ReleaseTriggerModifiersAsync();
                KeySender.Tap(VirtualKeys.LWin);
                return ActionOutcome.Done;
            default:
                await context.ReleaseTriggerModifiersAsync();
                var (vk, modifiers) = Shortcut(command);
                KeySender.Send(vk, modifiers);
                return ActionOutcome.Done;
        }
    }

    /// <summary>The Windows shortcut behind a system command.</summary>
    private static (ushort Vk, Modifiers Modifiers) Shortcut(SystemCommand command) => command switch
    {
        SystemCommand.MissionControl => (VirtualKeys.Tab, Modifiers.Command),
        SystemCommand.AppExpose => (VirtualKeys.Tab, Modifiers.Control | Modifiers.Option),
        SystemCommand.ShowDesktop => (VirtualKeys.D, Modifiers.Command),
        SystemCommand.NotificationCenter => (VirtualKeys.N, Modifiers.Command),
        SystemCommand.Spotlight => (VirtualKeys.S, Modifiers.Command),
        SystemCommand.EmojiPicker => (VirtualKeys.OemPeriod, Modifiers.Command),
        SystemCommand.Dictation => (VirtualKeys.H, Modifiers.Command),
        SystemCommand.ForceQuit => (VirtualKeys.Escape, Modifiers.Control | Modifiers.Shift),
        _ => (VirtualKeys.A, Modifiers.Command),   // Quick Settings
    };

    private static ActionOutcome Open(string uri, string? failure = null)
    {
        try
        {
            ShellLauncher.Open(uri);
            return ActionOutcome.Done;
        }
        catch (Win32Exception e)
        {
            return new ActionOutcome.Failed(failure ?? e.Message);
        }
    }

    /// <summary>Flips the app and system themes (Settings › Personalisation › Colours) and tells running apps.</summary>
    private static async Task<ActionOutcome> ToggleDarkModeAsync()
    {
        using (var key = Registry.CurrentUser.CreateSubKey(PersonalizeKey, writable: true))
        {
            var light = key.GetValue("AppsUseLightTheme") is not int value || value != 0;
            var next = light ? 0 : 1;
            key.SetValue("AppsUseLightTheme", next, RegistryValueKind.DWord);
            key.SetValue("SystemUsesLightTheme", next, RegistryValueKind.DWord);
            // Broadcasting can wait on slow windows; never on the UI thread.
            await Task.Run(() => SendMessageTimeoutW(HWND_BROADCAST, WM_SETTINGCHANGE, 0, "ImmersiveColorSet", SMTO_ABORTIFHUNG, 200, out _));
            return new ActionOutcome.SuccessWithMessage(light ? "Dark mode on" : "Light mode on");
        }
    }

    /// <summary>Steps a built-in display's brightness by 10 % through WMI (external monitors don't support it).</summary>
    private static ActionOutcome AdjustBrightness(bool up)
    {
        try
        {
            using var levels = new ManagementObjectSearcher(@"root\WMI", "SELECT CurrentBrightness FROM WmiMonitorBrightness WHERE Active=TRUE");
            var current = levels.Get().Cast<ManagementBaseObject>().Select(o => Convert.ToInt32(o["CurrentBrightness"], System.Globalization.CultureInfo.InvariantCulture)).FirstOrDefault(-1);
            if (current < 0) return new ActionOutcome.Failed("This display's brightness can't be changed by apps.");
            var target = Math.Clamp(current + (up ? 10 : -10), 0, 100);
            using var methods = new ManagementObjectSearcher(@"root\WMI", "SELECT * FROM WmiMonitorBrightnessMethods WHERE Active=TRUE");
            foreach (var monitor in methods.Get().Cast<ManagementObject>())
            {
                using (monitor)
                {
                    monitor.InvokeMethod("WmiSetBrightness", [1u, (byte)target]);
                }
            }
            return new ActionOutcome.SuccessWithMessage($"Brightness {target} %");
        }
        catch (ManagementException)
        {
            return new ActionOutcome.Failed("This display's brightness can't be changed by apps.");
        }
    }
}
