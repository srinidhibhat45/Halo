# Halo for Windows

Press a shortcut and a ring of actions appears around the pointer; point and click, or hold the
shortcut, point and let go. The Windows version of Halo, sharing its behaviour and configuration
format with the macOS app. See [ARCHITECTURE.md](ARCHITECTURE.md) for how it is built.

Requirements: Windows 10 (21H1 or later) or Windows 11, x64. Windows 11 is recommended (Segoe Fluent
Icons, the Fluent look and Snipping Tool's area snip).

## Install

1. Download `HaloSetup.exe` from the latest [GitHub Release](https://github.com/srinidhibhat45/Halo/releases/latest).
2. Run it. Halo installs for your user only (no admin rights) into `%LocalAppData%\Halo`, adds
   Start menu and desktop shortcuts and starts. Its icon sits in the notification area.

**SmartScreen warning.** The installer is not code-signed yet, so Windows may show "Windows
protected your PC". Choose **More info** → **Run anyway**. (Your browser may also ask you to keep
the download.) Signing the installer removes this; see *Releasing* below.

**Updates** are automatic: Halo checks GitHub Releases on launch and daily, downloads a new version
in the background and offers **Restart to Update** in the tray menu and in Settings › About. Turn
automatic checks off in Settings › About.

**Uninstall** from Settings › Apps › Installed apps › Halo. Your configuration in
`%APPDATA%\Halo` is kept.

## Use

- Default shortcut: **Ctrl+Shift+Alt+H**. Change it in Settings › General (click the shortcut,
  press the new one; Esc cancels, Backspace clears). To open the ring from a mouse button, assign
  the shortcut to that button in your mouse's software (Logi Options+, Razer Synapse,
  X-Mouse Button Control…).
- Tap the shortcut: the ring stays open; click a slot, press its number (1–9, 0), or use the arrow
  keys/Tab and Enter. Hold the shortcut, point at a slot and let go to run it in one stroke.
- Rest on a folder to open it; Backspace, Esc or a click on the centre goes back; click outside
  or press Esc to close. Ctrl+click a slot to edit it in Settings.
- App rings: Settings › **Add App Ring…** picks an app; its ring replaces the Everywhere ring while
  that app is in front (empty slots show the Everywhere ring's actions).
- Configuration: `%APPDATA%\Halo\config.json` (with `config.backup.json`). Export/import in
  Settings › General; exported files open on the Mac too (key codes are platform-specific, so
  re-record keyboard shortcuts after moving between platforms).

## Build

Needs the .NET 10 SDK.

```powershell
cd windows
dotnet build Halo.Windows.sln          # zero warnings: warnings are errors
dotnet test tests/Halo.Core.Tests      # Halo.Core unit tests (run on any OS)
dotnet run --project src/Halo.App      # run from source (updates are off when not installed)
```

On macOS or Linux the solution builds (`EnableWindowsTargeting` is set) and the Core tests run,
but the app itself only runs on Windows.

The icon (`src/Halo.App/Assets/Halo.ico`, `HaloLogo.png`) is generated from the macOS icon's
design by a script that needs nothing but .NET: `dotnet run build/make-icon.cs -- src/Halo.App/Assets`.

## Releasing

Releases are built by CI. `build/release-windows.yml` (move it to `.github/workflows/`) runs on
every pushed `v*` tag on `windows-latest`: it tests, builds, runs `build/pack.ps1` and attaches the
files to that tag's GitHub Release (creating it if needed). To build the same packages locally:

```powershell
./build/pack.ps1 -Version 1.2.0
# optional, for delta updates: -PreviousReleasesFrom https://github.com/srinidhibhat45/Halo
```

`pack.ps1` publishes a self-contained `win-x64` build, installs the matching `vpk` (Velopack CLI)
into `artifacts/tools`, and runs `vpk pack --packId Halo --packVersion <ver> --mainExe Halo.exe
--icon …`. Output in `artifacts/releases`:

| File | What it is |
|---|---|
| `HaloSetup.exe` | The installer users download (copy of `Halo-win-Setup.exe`) |
| `Halo-win-Portable.zip` | Runs without installing (no automatic updates) |
| `Halo-<ver>-full.nupkg` (+ `-delta.nupkg`) | Update packages |
| `releases.win.json`, `assets.win.json`, `RELEASES` | The feed the updater reads |

The updater (`Velopack.UpdateManager` with `GithubSource`) reads the newest **published**,
non-prerelease GitHub Release that has `releases.win.json`; draft releases are invisible to it.
Version numbers come from the tag (`v1.2.0` → `1.2.0`) and must be SemVer.

To sign the installer later, add an Authenticode certificate to CI and pass vpk's signing options
(`--signParams` or `--azureTrustedSignFile`) in `pack.ps1`.

## Troubleshooting

- **The shortcut does nothing.** Another app may use it; pick another in Settings › General. Apps
  running as administrator don't receive Halo's shortcuts or window commands unless Halo also runs
  as administrator (Windows blocks lower-privilege input into them).
- **Glass looks solid.** Turn on Settings › Personalisation › Colours › Transparency effects.
- **The ring doesn't animate.** Windows' Settings › Accessibility › Visual effects › Animation
  effects is off; Halo then cross-fades instead (or set Animation speed above 0 in Appearance).
