using System.Windows;
using Halo.App.Apps;
using Halo.App.Overlay;
using Halo.App.Rendering;
using Halo.App.Settings.Dialogs;
using Halo.App.Settings.ViewModels;
using Halo.App.Trigger;
using Halo.Core;
using Halo.Core.Catalog;
using Halo.Core.Editing;
using Microsoft.Win32;

namespace Halo.App.Settings;

/// <summary>
/// The settings window's <see cref="IEditorServices"/>: dialogs owned by the settings window, and
/// the "setup" step for templates that need details (an app, a URL, keys, a script…).
/// </summary>
internal sealed class EditorServices(
    Func<Window?> owner, SlotArtwork artwork, AppIconCache icons, InstalledApps apps, TriggerHook hook, OverlayController overlay) : IEditorServices
{
    public SlotArtwork Artwork => artwork;
    public AppIconCache Icons => icons;
    public InstalledApps Apps => apps;

    public (HaloAction Action, string? Title)? ChooseAction()
    {
        var picker = new PickerViewModel("Choose an Action", PickerViewModel.Templates());
        AddApps(picker, "Open an App");
        if (new PickerWindow(picker, owner()).Choose() is not { } chosen) return null;
        return chosen.Payload switch
        {
            InstalledApp app => (new AppAction(app.ToTarget()), null),
            ActionTemplate template when template.NeedsSetup => SetUp(template) is { } action ? (action, null) : null,
            ActionTemplate template => (template.Action, null),
            _ => null,
        };
    }

    public InstalledApp? ChooseApp(string title)
    {
        var picker = new PickerViewModel(title, []);
        AddApps(picker, "Apps");
        return new PickerWindow(picker, owner()).Choose()?.Payload as InstalledApp;
    }

    public bool Confirm(string title, string message) =>
        Message(message, title, MessageBoxButton.OKCancel, MessageBoxImage.Question) == MessageBoxResult.OK;

    public void TryRing(RingTarget target) => overlay.TryRing(target);

    /// <summary>Running apps first, then the Start menu (added when its background scan finishes).</summary>
    private void AddApps(PickerViewModel picker, string group)
    {
        var running = InstalledApps.Running();
        picker.AddItems(PickerViewModel.Apps(running, icons, $"{group}: running"));
        var known = new HashSet<string>(running.Select(a => a.BundleId), StringComparer.OrdinalIgnoreCase);
        var scan = apps.LoadAsync();
        void AddInstalled(IReadOnlyList<InstalledApp> installed) =>
            picker.AddItems(PickerViewModel.Apps(installed.Where(a => !known.Contains(a.BundleId)), icons, group));
        if (scan.IsCompletedSuccessfully) AddInstalled(scan.Result);
        else scan.ContinueWith(t => AddInstalled(t.Result), CancellationToken.None, TaskContinuationOptions.OnlyOnRanToCompletion, TaskScheduler.FromCurrentSynchronizationContext());
    }

    /// <summary>Asks for what a template needs; null when the user cancels.</summary>
    private HaloAction? SetUp(ActionTemplate template)
    {
        switch (template.Action)
        {
            case AppAction app:
                return ChooseApp(template.Title) is { } chosen ? new AppAction(chosen.ToTarget(app.Target.Behavior)) : null;
            case AppShortcutAction:
                if (ChooseApp("Send a Shortcut to…") is not { } target) return null;
                if (Record("App Shortcut", $"Press the shortcut to send to {target.Name}.") is not { } combo) return null;
                var title = Prompt("App Shortcut", $"What does {combo.DisplayString} do in {target.Name}? (shown on the ring)", "", multiline: false) ?? "";
                return new AppShortcutAction(new AppShortcut(target.BundleId, target.Name, title, combo));
            case UrlAction url:
                return Prompt(template.Title, "Web address or app link:", url.Link.Url, multiline: false) is { } address ? new UrlAction(new WebLink(address.Trim())) : null;
            case FileAction:
                return ChoosePath() is { } path ? new FileAction(new FileTarget(path)) : null;
            case KeystrokeAction:
                return Record(template.Title, "Press the keys to send to the app in front.") is { } keys ? new KeystrokeAction(keys) : null;
            case TextAction:
                return Prompt(template.Title, "Text to paste. You can use {date}, {time}, {clipboard} and {selection}.", "", multiline: true) is { } text
                    ? new TextAction(new TextSnippet(text)) : null;
            case ShellAction shell:
                return Prompt(template.Title, $"{shell.Script.ShellTitle()} script (runs hidden, stops after 30 seconds):", shell.Script.Source, multiline: true) is { } source
                    ? new ShellAction(shell.Script with { Source = source }) : null;
            case AiPromptAction ai:
                if (ChooseService() is not { } service) return null;
                return Prompt(template.Title, "Prompt. {selection} is replaced by the selected text.", ai.Prompt.Template, multiline: true) is { } prompt
                    ? new AiPromptAction(new AiPrompt(service, prompt)) : null;
            default:
                Message($"{template.Title} is set up in the full ring editor, which is coming in the next update.", "Halo",
                    MessageBoxButton.OK, MessageBoxImage.Information);
                return null;
        }
    }

    private MessageBoxResult Message(string message, string title, MessageBoxButton buttons, MessageBoxImage image) =>
        owner() is { } window
            ? MessageBox.Show(window, message, title, buttons, image, MessageBoxResult.Cancel)
            : MessageBox.Show(message, title, buttons, image, MessageBoxResult.Cancel);

    private string? Prompt(string title, string message, string initial, bool multiline) =>
        new PromptWindow(title, message, initial, multiline, owner()).Ask();

    private KeyCombo? Record(string title, string message) => new ShortcutWindow(hook, title, message, owner()).Record();

    private string? ChoosePath()
    {
        var kinds = new PickerViewModel("Open File or Folder",
        [
            new PickerItem("A file…", "Opens with its default app", "Choose", PickerViewModel.Glyph("doc"), null, null, "file", []),
            new PickerItem("A folder…", "Opens in File Explorer", "Choose", PickerViewModel.Glyph("folder"), null, null, "folder", []),
        ]);
        switch (new PickerWindow(kinds, owner()).Choose()?.Payload)
        {
            case "file":
                var file = new OpenFileDialog { Title = "Choose a File" };
                return (owner() is { } fileOwner ? file.ShowDialog(fileOwner) : file.ShowDialog()) == true ? file.FileName : null;
            case "folder":
                var folder = new OpenFolderDialog { Title = "Choose a Folder" };
                return (owner() is { } folderOwner ? folder.ShowDialog(folderOwner) : folder.ShowDialog()) == true ? folder.FolderName : null;
            default:
                return null;
        }
    }

    private AiService? ChooseService()
    {
        var services = new PickerViewModel("Choose an AI",
            Enum.GetValues<AiService>().Where(s => s != AiService.Custom).Select(s => new PickerItem(
                s.DisplayName(), s.UrlTemplate() is null ? "Copies the prompt and opens the site" : "Opens with the prompt filled in",
                "Services", PickerViewModel.Glyph("sparkles"), null, null, s, [])));
        return new PickerWindow(services, owner()).Choose()?.Payload is AiService service ? service : null;
    }
}
