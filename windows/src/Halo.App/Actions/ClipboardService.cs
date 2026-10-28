using System.Runtime.InteropServices;
using System.Windows;
using Halo.App.Interop;
using Halo.Core;

namespace Halo.App.Actions;

/// <summary>
/// Clipboard access for snippets and prompts: snapshot and restore what the user had, put text,
/// and copy the selection of the app in front. Call on the UI (STA) thread.
/// </summary>
/// <remarks>Another app may hold the clipboard open for a moment, so every call retries briefly.</remarks>
internal static class ClipboardService
{
    /// <summary>A copy of every format on the clipboard that can be read, or null when it is empty.</summary>
    public static IDataObject? Snapshot()
    {
        var current = Retry(Clipboard.GetDataObject);
        if (current is null) return null;
        var copy = new DataObject();
        var any = false;
        foreach (var format in current.GetFormats(autoConvert: false))
        {
            try
            {
                if (current.GetData(format, autoConvert: false) is { } data)
                {
                    copy.SetData(format, data);
                    any = true;
                }
            }
            catch (Exception e) when (e is ExternalException or OutOfMemoryException)
            {
                // Some formats are rendered on demand by their owner and can't be copied; skip them.
            }
        }
        return any ? copy : null;
    }

    /// <summary>Puts a snapshot back (or empties the clipboard when there was nothing).</summary>
    public static void Restore(IDataObject? snapshot)
    {
        if (snapshot is null) Retry(() => { Clipboard.Clear(); return true; });
        else Retry(() => { Clipboard.SetDataObject(snapshot, copy: true); return true; });
    }

    public static void SetText(string text) => Retry(() => { Clipboard.SetText(text); return true; });

    public static string GetText() => Retry(() => Clipboard.ContainsText() ? Clipboard.GetText() : "") ?? "";

    /// <summary>
    /// Copies the selection of the app in front (Ctrl+C) and returns it as text, leaving the
    /// clipboard as it was. Empty when nothing is selected.
    /// </summary>
    public static async Task<string> CopySelectionAsync(ActionContext context)
    {
        var snapshot = Snapshot();
        var before = Native.GetClipboardSequenceNumber();
        await context.ReleaseTriggerModifiersAsync();
        KeySender.Send(VirtualKeys.C, Modifiers.Control);
        var deadline = Environment.TickCount64 + 600;
        while (Native.GetClipboardSequenceNumber() == before && Environment.TickCount64 < deadline)
        {
            await Task.Delay(20);
        }
        var copied = Native.GetClipboardSequenceNumber() != before;
        var text = copied ? GetText() : "";
        if (copied) Restore(snapshot);
        return text;
    }

    /// <summary>Pastes <paramref name="text"/> into the app in front (Ctrl+V), then restores the clipboard.</summary>
    public static async Task PasteAsync(string text, ActionContext context)
    {
        var snapshot = Snapshot();
        SetText(text);
        await context.ReleaseTriggerModifiersAsync();
        KeySender.Send(VirtualKeys.V, Modifiers.Control);
        // Apps read the clipboard asynchronously after Ctrl+V; give them a moment.
        await Task.Delay(350);
        Restore(snapshot);
    }

    private static T? Retry<T>(Func<T?> read)
    {
        for (var attempt = 0; ; attempt++)
        {
            try
            {
                return read();
            }
            catch (ExternalException) when (attempt < 5)
            {
                Thread.Sleep(30);
            }
        }
    }
}
