using System.ComponentModel;
using System.Management;
using System.Runtime.InteropServices;
using Halo.Core;
using Halo.Core.Catalog;

namespace Halo.App.Actions;

/// <summary>Runs any action on the UI thread and reports how it went; never throws.</summary>
internal static class ActionRunner
{
    public static async Task<ActionOutcome> RunAsync(HaloAction action, ActionContext context)
    {
        var availability = action.Availability();
        if (!availability.IsAvailable) return new ActionOutcome.Failed(availability.Reason ?? "This action can't run on Windows.");
        try
        {
            return action switch
            {
                AppAction a => AppActions.Run(a.Target, context),
                AppShortcutAction a => await AppActions.SendShortcutAsync(a.Shortcut, context),
                UrlAction u => ContentActions.OpenUrl(u.Link),
                FileAction f => ContentActions.OpenFile(f.Target),
                KeystrokeAction k => await SystemActions.SendKeysAsync(k.Combo, context, confirm: false),
                EditAction e => await SystemActions.SendKeysAsync(e.Command.KeyCombo(), context, confirm: e.Command is EditCommand.Copy or EditCommand.Cut),
                MediaAction m => await SystemActions.MediaAsync(m.Command, context),
                SystemAction s => await SystemActions.RunAsync(s.Command, context),
                WindowAction w => await WindowActions.RunAsync(w.Command, context),
                ScreenshotAction s => ContentActions.Screenshot(s.Options, context),
                ShellAction s => await ContentActions.RunScriptAsync(s.Script),
                TextAction t => await ContentActions.TextAsync(t.Snippet, context),
                AiPromptAction p => await ContentActions.AiPromptAsync(p.Prompt, context),
                MacroAction m => await RunMacroAsync(m.Macro, context),
                FolderAction => new ActionOutcome.Failed("Folders open in the ring."),
                _ => new ActionOutcome.Failed("This action can't run on Windows."),
            };
        }
        catch (Exception e) when (e is Win32Exception or IOException or UnauthorizedAccessException or ExternalException
                                      or InvalidOperationException or ManagementException)
        {
            return new ActionOutcome.Failed(e.Message);
        }
    }

    /// <summary>Runs a Smart Action's steps in order with their delays, stopping at the first failure.</summary>
    private static async Task<ActionOutcome> RunMacroAsync(Macro macro, ActionContext context)
    {
        if (macro.Steps.Count == 0) return new ActionOutcome.Failed("This Smart Action has no steps.");
        var confirm = false;
        for (var i = 0; i < macro.Steps.Count; i++)
        {
            var step = macro.Steps[i];
            if (step.Action is FolderAction or MacroAction) return new ActionOutcome.Failed($"Step {i + 1}: Smart Actions can't contain folders or other Smart Actions.");
            var outcome = await RunAsync(step.Action, context);
            if (outcome is ActionOutcome.Failed failed) return new ActionOutcome.Failed($"Step {i + 1}: {failed.Message}");
            confirm |= outcome is ActionOutcome.Success { Confirm: true };
            if (step.DelayAfter > 0) await Task.Delay(TimeSpan.FromSeconds(Math.Min(step.DelayAfter, 30)));
        }
        return new ActionOutcome.Success(confirm);
    }
}
