# Halo for Windows: architecture

The Windows twin of the macOS app (`../Sources`). Same behaviour, same config JSON, Windows-native
UI. C# / .NET 10, WPF with the built-in Fluent theme (`ThemeMode="System"`), Win32 interop via
`LibraryImport` (classic COM interop only for two shell interfaces). No UI framework dependency.
NuGet: `Velopack` (updates), `System.Management` (laptop brightness).

```
windows/
  Halo.Windows.sln
  Directory.Build.props        nullable, implicit usings, warnings are errors
  src/Halo.Core/               net10.0, no Windows APIs, unit-tested on any OS
    Model/                     HaloAction (+ payloads), Ring/Slot/IconSpec/RingColor, KeyCombo, AppSettings, HaloConfig
    Serialization/             HaloJson: the Mac app's exact JSON shape, tolerant decoding
    Geometry/                  RingGeometry, ArcGeometry, RingMetrics
    Interaction/               RingInteraction (tap/hold state machine), RingLevels (session levels,
                               gap closing, edit destinations), RingLayout (hit-testing incl. fanned folders)
    Motion/                    Spring (closed-form damped spring), RingMotion (springs, bloom, timings)
    Catalog/                   ActionPresentation (titles, symbols, availability), ActionCatalog,
                               DefaultRings, SymbolGlyphs (SF Symbols name → Segoe Fluent Icons)
    Editing/                   RingTarget, RingAddress, ConfigEditing (pure, undoable edits)
    Storage/                   ConfigFile: %APPDATA%\Halo\config.json, backup, corrupt-file recovery
  tests/Halo.Core.Tests/       xUnit: every Mac HaloCore test ported, plus layout, springs, editing, Mac JSON
  src/Halo.App/                net10.0-windows WPF, assembly Halo.exe, PerMonitorV2 manifest
    Program.cs                 Velopack hooks → single instance → HaloApplication
    App.xaml(.cs)              HaloApplication: wiring, tray menu, notices, shutdown
    AppModel.cs                IConfigStore: the config, undo/redo, debounced save
    Mvvm.cs                    ObservableObject, RelayCommand
    Interop/                   Native (P/Invoke), HookThread, KeySender, WindowTools, Displays,
                               ShellItems (icons, .lnk targets, known folders), TrayIcon
    Trigger/                   TriggerHook (combo, navigation keys, recording), KeyLabels
    Overlay/                   OverlayController, OverlayWindow, BackdropCapture, Toasts (+ Announcer)
    Rendering/                 RingViewModel, RingCanvas, RingAnimator, ClassicPainter, GlassPainter,
                               PaintContext, SlotArtwork, RingPalette (+ SystemAppearance)
    Actions/                   ActionRunner + AppActions, SystemActions, WindowActions, ContentActions,
                               ClipboardService, ActionTypes (context, outcome, ShellLauncher)
    Apps/                      InstalledApps (Start-menu .lnk + running apps), AppIconCache
    Platform/                  UpdateService (Velopack), StartWithWindows (HKCU Run), SingleInstance
    Settings/                  SettingsWindow, Views/ (pages), ViewModels/, Dialogs/, IEditorServices, EditorServices
  build/                       pack.ps1, release-windows.yml, make-icon.cs
```

## Data flow

- `AppModel` holds the `HaloConfig` (an immutable record). Every change is
  `IConfigStore.Update(undoName, config => newConfig)`: it records undo (same-named edits within
  1 s coalesce, so a slider drag is one undo step), restarts a 400 ms save timer and raises
  `ConfigChanged(old, new)` on the UI thread. `HaloApplication` forwards that to the overlay
  (trigger, appearance, icon prefetch), Start-with-Windows and the update schedule.
- The overlay snapshots the resolved ring when it opens (`HaloConfig.ResolveRing(app ids)` →
  `RingLevels`); edits made while it is open apply next time.
- `RingViewModel` is what `RingCanvas` draws. The overlay, the ring editor and the Appearance
  preview each own one. Owners mutate it and call `NotifyChanged()`; the canvas re-targets its
  springs (`RingAnimator.Sync`) and renders every composition frame until they rest.

## Threads

- UI thread (STA): everything except the hooks. Actions are `async` and resume on it (clipboard and
  shell COM need STA).
- Hook thread (`HookThread`): owns `WH_KEYBOARD_LL` (always) and `WH_MOUSE_LL` (only while the ring
  is open) and a bare `GetMessage` loop. Its filters only read volatile fields, decide to swallow
  synchronously, and `BeginInvoke` everything else to the UI dispatcher, so a busy UI can never
  slow typing or get the hook dropped by Windows' hook timeout. Hooks are unhooked when the thread
  exits (`Dispose` on app exit). Callbacks are `[UnmanagedCallersOnly]` function pointers: nothing
  for the GC to collect.

## Trigger and input (`TriggerHook`)

- The combo (default Ctrl+Shift+Alt+H; `keyCode` is a Windows VK, `command` = Win, `option` = Alt)
  is matched on key-down with exactly its modifiers (tracked from hook events; modifiers held for
  over a second are re-checked against `GetAsyncKeyState`, so a release missed on the secure desktop
  can't wedge it). Press is reported once, auto-repeat is latched and swallowed, the release of the
  key is reported. With Alt or Win in the combo a dummy key (VK 0xE8) is tapped right after, so
  their release doesn't open a menu bar or Start.
- While the ring is open: Esc, Enter, Space, Backspace, Delete, Tab/Shift+Tab, arrows, top-row and
  keypad digits are swallowed (only without Ctrl/Alt/Win) along with their key-ups.
- Halo's own `SendInput` events carry `dwExtraInfo = 0x48414C4F` and pass through untouched; other
  injected input (mouse software sending the combo) is handled normally.
- Recording (General › Ring shortcut, shortcut dialogs) goes through the hook, so Win+… combos can
  be recorded; it swallows non-modifier keys until it ends (also when the window deactivates).

## Overlay (`OverlayController`)

Port of the Mac `OverlayController`/`RingSession` with the same structure and names.

- Window: borderless, `AllowsTransparency`, topmost; `WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW |
  WS_EX_TOPMOST | WS_EX_LAYERED`, `WM_MOUSEACTIVATE` → `MA_NOACTIVATE`. Pre-warmed at launch.
  Placed with `SetWindowPos` in physical pixels on the monitor under the pointer, the ring kept
  inside the work area (`RingMetrics.ClampRadius` + 8 px); per-monitor DPI handled by WPF.
- Every frame (`CompositionTarget.Rendering`) while open: pointer → DIP offset → `RingLayout.HitTest`
  (hold: 16 px dead zone from the press point, unbounded; tap: hub = target, bounded by
  `MaxHitRadius`; 5° hysteresis; fanned folders: children on the outer arc, other root slots switch).
  The same frame toggles `WS_EX_TRANSPARENT` so clicks off the ring reach the app below, times the
  folder dwell (0.13 s, tap and hold) and synthesises a missed trigger release after 0.15 s of
  released modifiers.
- Clicks are decided by geometry on mouse-up; right-click closes; Ctrl+click opens Settings at that
  slot (`RingLevels.EditDestination`, mapping display indices back through closed gaps and
  inherited slots). The low-level mouse hook closes the ring on any press outside it (the click
  still reaches its target). Scroll over a highlighted volume/brightness slot adjusts it.
- Dismissal also on foreground change (WinEvent `EVENT_SYSTEM_FOREGROUND`, after a 0.3 s grace),
  session switch/lock, display change and suspend. A 0.5 s watchdog guarantees keys, polling,
  hooks and the window are released whenever no session is open.
- Gap closing (`closesGaps`, default on): `RingLevels` shows `Ring.Compacted()` at every level.
- Run: the slot pulses (≈80 ms), the ring dismisses, then the action runs; window/full-screen
  captures wait until the window is gone. Outcomes show a toast near the ring; every highlight,
  level change and outcome is announced to Narrator (UIA notification events).

## Rendering and motion

- `RingCanvas : FrameworkElement` draws with `DrawingContext` (no visual tree per slot): Classic
  (Logitech-style bubbles, tab on folders, outward tooltip with notch, adjustable dot, numbers) or
  Glass (rounded annular sectors with a frosted backdrop: a downsampled, box-blurred screen
  snapshot taken just before showing, since WPF can't blur other windows; solid when Windows
  transparency effects are off or in high contrast).
- `RingAnimator` holds `Halo.Core.Motion.Spring`s (closed-form damped oscillator, exact for any
  frame time; re-targeting keeps velocity). Open = sequential bloom: hub first, then each slot
  travels out from the centre, clockwise from the top, 30 ms apart, spring (0.28 s, ζ 0.72);
  ≈0.46 s for eight. The editor builds its preview the same way. Dismiss: whole ring to 0.45 scale
  + fade (critically damped, 0.2 s). Highlight, fan-out/in (stagger from the centre child), root
  dim, tooltip, hub hover and execute pulse are springs too. Windows "Animation effects" off →
  cross-fades only; speed 0 → snap. Input never waits: hit-testing uses the final layout.
- Icons: SF Symbols names (shared config) → Segoe Fluent Icons code points (`SymbolGlyphs`, newest
  glyph first with a long-standing fallback, chosen by what the installed font has); real app icons
  via `IShellItemImageFactory` (exe, .lnk or `shell:AppsFolder\<AUMID>`), cached.

## Actions (Windows mapping)

| Kind | Windows |
|---|---|
| app open/toggle/quit | match running app windows by exe name / AUMID (UWP frame-host aware); activate (AttachThreadInput), launch path/.lnk/AUMID/exe; toggle minimises; quit posts SC_CLOSE |
| appShortcut | bring the app's window forward if needed, send the combo, optionally return to the previous window |
| url / file | ShellExecute; open-with browser; reveal = `explorer /select,` |
| keystroke, edit | SendInput after the trigger's modifiers are released (≤300 ms, then released virtually); edit = Ctrl+C/X/V, Ctrl+Shift+V, Ctrl+Z/Y/A/F |
| media | VK_MEDIA_* / VK_VOLUME_*; brightness via WMI (built-in displays) |
| screenshot | area → `ms-screenclip:`; window/screen → GDI capture to clipboard or Pictures\Screenshots; tools → Snipping Tool |
| system | Task View Win+Tab, Switch Windows Ctrl+Alt+Tab, Show Desktop Win+D, Start (Win), Notifications Win+N, Search Win+S, Copilot `ms-copilot:`, Lock `LockWorkStation`, display off `SC_MONITORPOWER`, Sleep `SetSuspendState`, screen saver, Emoji Win+., Voice typing Win+H, Dark mode (HKCU Personalize + `WM_SETTINGCHANGE "ImmersiveColorSet"`), Task Manager Ctrl+Shift+Esc, Settings `ms-settings:`, Quick Settings Win+A (Windows-only case) |
| window | halves/centre via `SetWindowPos` (async, invisible-border aware) on the window's monitor work area; maximise toggles; next monitor keeps relative place; minimise; close; full screen = F11 |
| shell | `shell` null/powershell → Windows PowerShell `-EncodedCommand`; `pwsh`; `cmd` (temp .cmd); other exe reads stdin. Hidden, 30 s timeout |
| text | paste (clipboard snapshot → Ctrl+V → restore) or type (KEYEVENTF_UNICODE); {date} {time} {clipboard} {selection} |
| aiPrompt | copy selection, fill {selection}, open ChatGPT/Claude/Perplexity prefill URL, else copy + open |
| macro | steps in order with delays, stop at the first failure |
| shortcut, appleScript, menuItem, DND | shown, marked unavailable (`ActionPresentation.Availability`) |

## Editor contracts (for the full ring editor)

The settings window renders pages through data templates keyed on view-model types, so a new
editor replaces `Views/RingPage.xaml` (and may add views) without touching the plumbing. These are
the stable seams:

- `IConfigStore` (`AppModel`): `Config`, `ConfigChanged(old, new)`, `Update(undoName, edit)`,
  `Undo/Redo/CanUndo/CanRedo/UndoName/RedoName`. All edits are pure functions in
  `Halo.Core.Editing.ConfigEditing` (`RingAt`, `UpdatingRing`, `SettingSlot`, `AssigningAction`,
  `AddingProfile`, `RemovingProfile`, `UpdatingProfile`, `NewProfile`, `Breadcrumb`) addressed by
  `RingAddress(RingTarget target, IReadOnlyList<int> path)`; `Ring` itself has `WithSlot`,
  `Resized`, `Swapped`, `Moved`, `Cleared`, `RingAt`, `UpdatingRing`, `Compacted`.
- `RingEditorViewModel(IConfigStore, IEditorServices, RingTarget)` — one ring level:
  - navigation: `Target`, `Address`, `IsInFolder`, `Breadcrumb`, `EnterFolder(slot)`, `Show(address, slot)`, `BackCommand`;
  - content: `CurrentRing`, `Slots` (`ObservableCollection<SlotItemViewModel>`), `SlotCount` (set = resize), `SlotCountChoices`;
  - preview: `Preview` (`RingViewModel`, editor mode) + `Artwork` → host a `RingCanvas`; `RingCanvas.HitTest(point)` resolves clicks/drops to `HitTarget.SlotHit/Hub`; set `Preview.Highlighted` for hover and call `NotifyChanged()`;
  - selection: `SelectedIndex`, `SelectedSlot`;
  - editing: `Assign(action, title)`, `ChooseActionCommand`, `ClearSlotCommand`, `OpenFolderCommand`, `Swap(a, b)`, `Move(from, to)`, `SetIcon(IconSpec?)`, `SetTint(RingColor?)`, `SlotLabel` (+ `SlotLabelPlaceholder`, `CanEditLabel`), `UndoCommand`, `RedoCommand`, `TryItCommand`;
  - app rings: `IsAppRing`, `RingName`, `IsEnabled`, `InheritsGlobalSlots`, `RemoveAppRingCommand`, `Removed` event.
- `SlotItemViewModel`: `Index`, `Number`, `Slot`, `Title`, `Subtitle`, `Glyph`, `AppIcon`, `IsEmpty`,
  `IsFolder`, `IsInherited`, `AvailabilityNote`, `AutomationName`.
- `PickerViewModel(title, IEnumerable<PickerItem>)`: `Query`, `Items`, `Selected`, `AddItems`;
  factories `Templates()` (catalog, Mac-only kinds disabled with a note) and `Apps(...)`.
  `PickerItem(Title, Subtitle, Group, Glyph, Icon, Note, Payload, Keywords)` with `Payload` an
  `ActionTemplate` or `InstalledApp`.
- `IEditorServices`: `Artwork`, `Icons`, `Apps`, `ChooseAction()` (library + apps + per-template
  setup: app pickers, URL/text/script/prompt dialogs, shortcut recorder, file/folder dialogs),
  `ChooseApp(title)`, `Confirm(title, message)`, `TryRing(target)`.
- Not done yet (for the full editor): drag and drop (use `Swap`/`Move`/`Assign` with
  `RingCanvas.HitTest`), the icon picker (`SymbolGlyphs.Names`, emoji, image → `ImageIcon`), tint
  picker, the Smart Action step editor, in-place payload editors (the current flow re-chooses the
  action), per-slot context menus.

## Config compatibility

`HaloJson` writes exactly the Mac shape (sorted keys, upper-case UUIDs, `{"type","value"}`
actions, Swift enum encoding for icons/colours, `null` trigger when cleared) and is tested against
a Mac-written sample. Platform-specific values travel as-is: `keyCode` is a Windows VK here and a
Carbon key code on the Mac, and `bundleID` is an exe name/AUMID here. A Windows-only system
command (`quickSettings`) reads as an empty slot on the Mac; Mac-only kinds round-trip untouched.
