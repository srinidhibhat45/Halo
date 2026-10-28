using Halo.App.Apps;
using Halo.App.Rendering;
using Halo.Core;
using Halo.Core.Editing;

namespace Halo.App.Settings;

/// <summary>
/// What the ring editor needs from the app (CONTRACT, see <c>windows/ARCHITECTURE.md</c>): dialogs,
/// icons and the live overlay. The settings window provides the implementation; tests or a future
/// editor can provide their own.
/// </summary>
internal interface IEditorServices
{
    /// <summary>Draws slot icons (shared with the overlay so icons load once).</summary>
    SlotArtwork Artwork { get; }

    AppIconCache Icons { get; }

    InstalledApps Apps { get; }

    /// <summary>
    /// Lets the user choose an action (searchable library plus installed apps), completing any
    /// details it needs (an app, a URL, a key combination…). Null when cancelled.
    /// </summary>
    (HaloAction Action, string? Title)? ChooseAction();

    /// <summary>Lets the user choose an app (running apps first, then the Start menu). Null when cancelled.</summary>
    InstalledApp? ChooseApp(string title);

    /// <summary>Asks a yes/no question; true for yes.</summary>
    bool Confirm(string title, string message);

    /// <summary>Opens the real overlay at the screen centre in tap mode with this ring.</summary>
    void TryRing(RingTarget target);
}
