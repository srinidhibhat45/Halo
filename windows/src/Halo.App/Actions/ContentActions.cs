using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Windows;
using System.Windows.Media.Imaging;
using Halo.App.Interop;
using Halo.App.Overlay;
using Halo.Core;
using Halo.Core.Catalog;
using static Halo.App.Interop.Native;

namespace Halo.App.Actions;

/// <summary>URLs, files, screenshots, scripts, text snippets and AI prompts.</summary>
internal static class ContentActions
{
    private const string SnippingToolAumid = "Microsoft.ScreenSketch_8wekyb3d8bbwe!App";
    private static readonly TimeSpan ScriptTimeout = TimeSpan.FromSeconds(30);

    public static ActionOutcome OpenUrl(WebLink link)
    {
        if (string.IsNullOrWhiteSpace(link.Url) || link.Url == "https://") return new ActionOutcome.Failed("Enter a web address for this slot.");
        try
        {
            if (string.IsNullOrWhiteSpace(link.OpenWithBundleId)) ShellLauncher.Open(link.Url);
            else ShellLauncher.Run(ShellLauncher.ResolveExecutable(link.OpenWithBundleId), link.Url);
            return ActionOutcome.Done;
        }
        catch (Win32Exception)
        {
            return new ActionOutcome.Failed($"Nothing could open {link.Url}.");
        }
    }

    public static ActionOutcome OpenFile(FileTarget target)
    {
        var path = target.ExpandedPath;
        if (path.Length == 0) return new ActionOutcome.Failed("Choose a file or folder for this slot.");
        if (!File.Exists(path) && !Directory.Exists(path)) return new ActionOutcome.Failed($"{target.DisplayName} isn't there any more.");
        try
        {
            if (target.Reveal) ShellLauncher.Run("explorer.exe", $"/select,\"{path}\"");
            else ShellLauncher.Open(path);
            return ActionOutcome.Done;
        }
        catch (Win32Exception e)
        {
            return new ActionOutcome.Failed(e.Message);
        }
    }

    public static ActionOutcome Screenshot(ScreenshotOptions options, ActionContext context)
    {
        switch (options.Mode)
        {
            case ScreenshotMode.Area:
                // Snipping Tool's area snip; it copies the result (and, on Windows 11, saves it).
                ShellLauncher.Open("ms-screenclip:");
                return ActionOutcome.Done;
            case ScreenshotMode.Toolbar:
                ShellLauncher.OpenPackagedApp(SnippingToolAumid);
                return ActionOutcome.Done;
        }

        RECT area;
        var window = context.TargetWindow;
        if (options.Mode == ScreenshotMode.Window && window != 0 && !WindowTools.IsShellSurface(window) && !IsIconic(window))
        {
            area = VisibleBounds(window);
        }
        else
        {
            area = Displays.At(context.Anchor.X, context.Anchor.Y).Bounds;
        }
        if (BackdropCapture.Capture(area.Left, area.Top, area.Width, area.Height) is not { } image) return new ActionOutcome.Failed("Windows didn't allow the screen capture.");

        if (options.ToClipboard)
        {
            Clipboard.SetImage(image);
            return new ActionOutcome.SuccessWithMessage("Screenshot copied");
        }
        var folder = ShellItems.ScreenshotsDirectory();
        Directory.CreateDirectory(folder);
        var file = Path.Combine(folder, $"Screenshot {DateTime.Now.ToString("yyyy-MM-dd HHmmss", CultureInfo.InvariantCulture)}.png");
        using (var stream = File.Create(file))
        {
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(image));
            encoder.Save(stream);
        }
        return new ActionOutcome.SuccessWithMessage("Saved to Screenshots");
    }

    /// <summary>
    /// Runs a script with no window: Windows PowerShell by default, or <c>pwsh</c>, <c>cmd</c>, or an
    /// executable that reads the script on stdin. Fails on a non-zero exit (with the first line of
    /// its error output) or after 30 seconds.
    /// </summary>
    public static async Task<ActionOutcome> RunScriptAsync(ScriptSource script)
    {
        if (string.IsNullOrWhiteSpace(script.Source)) return new ActionOutcome.Failed("This script is empty.");
        string? tempFile = null;
        try
        {
            var (info, stdin) = StartInfo(script, out tempFile);
            using var process = Process.Start(info) ?? throw new Win32Exception("The shell didn't start.");
            if (stdin is not null)
            {
                await process.StandardInput.WriteAsync(stdin);
                process.StandardInput.Close();
            }
            var errors = process.StandardError.ReadToEndAsync();
            var output = process.StandardOutput.ReadToEndAsync();
            using var timeout = new CancellationTokenSource(ScriptTimeout);
            try
            {
                await process.WaitForExitAsync(timeout.Token);
            }
            catch (OperationCanceledException)
            {
                process.Kill(entireProcessTree: true);
                return new ActionOutcome.Failed("The script took longer than 30 seconds and was stopped.");
            }
            await output;
            var error = (await errors).Trim();
            if (process.ExitCode == 0) return ActionOutcome.Confirmed;
            var firstLine = error.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).FirstOrDefault();
            return new ActionOutcome.Failed(firstLine ?? $"The script exited with code {process.ExitCode}.");
        }
        catch (Win32Exception e)
        {
            return new ActionOutcome.Failed($"{script.ShellTitle()} couldn't start: {e.Message}");
        }
        finally
        {
            if (tempFile is not null) TryDelete(tempFile);
        }
    }

    /// <summary>Pastes or types a snippet, with {date}, {time}, {clipboard} and {selection} filled in.</summary>
    public static async Task<ActionOutcome> TextAsync(TextSnippet snippet, ActionContext context)
    {
        if (snippet.Text.Length == 0) return new ActionOutcome.Failed("This snippet is empty.");
        var text = snippet.Text;
        if (text.Contains("{selection}", StringComparison.Ordinal)) text = text.Replace("{selection}", await ClipboardService.CopySelectionAsync(context), StringComparison.Ordinal);
        if (text.Contains("{clipboard}", StringComparison.Ordinal)) text = text.Replace("{clipboard}", ClipboardService.GetText(), StringComparison.Ordinal);
        var now = DateTime.Now;
        text = text.Replace("{date}", now.ToString("d", CultureInfo.CurrentCulture), StringComparison.Ordinal)
                   .Replace("{time}", now.ToString("t", CultureInfo.CurrentCulture), StringComparison.Ordinal);

        if (snippet.Method == TextMethod.Paste)
        {
            await ClipboardService.PasteAsync(text, context);
        }
        else
        {
            await context.ReleaseTriggerModifiersAsync();
            KeySender.Type(text);
        }
        if (snippet.PressReturn) KeySender.Send(VirtualKeys.Return);
        return ActionOutcome.Done;
    }

    /// <summary>
    /// Fills <c>{selection}</c> with the selected text and opens the AI service with the prompt
    /// prefilled; services without a prefill URL get the prompt on the clipboard instead.
    /// </summary>
    public static async Task<ActionOutcome> AiPromptAsync(AiPrompt prompt, ActionContext context)
    {
        var text = prompt.Template;
        if (prompt.UsesSelection)
        {
            var selection = await ClipboardService.CopySelectionAsync(context);
            if (string.IsNullOrWhiteSpace(selection)) return new ActionOutcome.Failed("Select some text first.");
            text = text.Replace("{selection}", selection, StringComparison.Ordinal);
        }

        var template = prompt.Service == AiService.Custom ? prompt.CustomUrlTemplate : prompt.Service.UrlTemplate();
        var url = template?.Replace("{prompt}", Uri.EscapeDataString(text), StringComparison.Ordinal);
        // Browsers and servers cap URL length; very long prompts go through the clipboard.
        if (url is not null && url.Length <= 8000) return OpenUrl(new WebLink(url));

        ClipboardService.SetText(text);
        var home = prompt.Service == AiService.Custom ? null : prompt.Service.HomeUrl();
        if (!string.IsNullOrEmpty(home)) OpenUrl(new WebLink(home));
        return new ActionOutcome.SuccessWithMessage(home is null ? "Prompt copied" : $"Prompt copied: paste it into {prompt.Service.DisplayName()}");
    }

    private static (ProcessStartInfo Info, string? Stdin) StartInfo(ScriptSource script, out string? tempFile)
    {
        tempFile = null;
        var info = new ProcessStartInfo
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden,
            RedirectStandardError = true,
            RedirectStandardOutput = true,
            WorkingDirectory = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        };
        switch (script.Shell?.Trim().ToLowerInvariant())
        {
            case null or "" or "powershell" or "powershell.exe" or "pwsh" or "pwsh.exe":
                info.FileName = script.Shell?.Trim().StartsWith("pwsh", StringComparison.OrdinalIgnoreCase) == true ? "pwsh.exe" : "powershell.exe";
                foreach (var a in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-EncodedCommand",
                             Convert.ToBase64String(Encoding.Unicode.GetBytes(script.Source)) })
                {
                    info.ArgumentList.Add(a);
                }
                return (info, null);
            case "cmd" or "cmd.exe":
                // Batch files support multi-line scripts; cmd /c on a string does not.
                tempFile = Path.Combine(Path.GetTempPath(), $"halo-{Guid.NewGuid():N}.cmd");
                File.WriteAllText(tempFile, "@echo off\r\nchcp 65001 >nul\r\n" + script.Source.ReplaceLineEndings("\r\n"), new UTF8Encoding(false));
                info.FileName = "cmd.exe";
                info.ArgumentList.Add("/d");
                info.ArgumentList.Add("/c");
                info.ArgumentList.Add(tempFile);
                return (info, null);
            default:
                var shell = ShellLauncher.ResolveExecutable(script.Shell!.Trim());
                if (!File.Exists(shell)) throw new Win32Exception($"{script.Shell} isn't available on Windows.");
                info.FileName = shell;
                info.RedirectStandardInput = true;
                return (info, script.Source);
        }
    }

    private static void TryDelete(string path)
    {
        try
        {
            File.Delete(path);
        }
        catch (IOException)
        {
            // Still locked by a straggling child process; the temp folder is cleaned eventually.
        }
    }
}
