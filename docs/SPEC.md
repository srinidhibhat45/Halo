# Halo — product and engineering spec

> Paths below are relative to `macos/` (the Mac app). The Windows port lives in `windows/` (see windows/ARCHITECTURE.md).

Halo is a native macOS menu-bar app that recreates (and extends) Logitech's Actions Ring: press a
global shortcut (usually assigned to a mouse button in the mouse's own software) and a ring of
customisable actions appears around the pointer. Point and click (or hold, point and release) to
run one. A configurator window lets the user design rings, per-app rings and nested rings.

Target: macOS 26+ (built and tested on macOS 27.2, Apple Silicon). Swift 6.4, SwiftUI + AppKit,
SwiftPM, Command Line Tools only (no Xcode). No third-party dependencies.

---

## 1. Architecture

```
Sources/HaloCore/          pure logic, no UI, unit-tested (swift test)
  Model/                   Action (+payloads), Ring/Slot/IconSpec/RingColor, AppSettings, HaloConfig, KeyCombo
  Geometry/RingGeometry    sector maths, pointer→slot, arrow/tab navigation
  Interaction/RingInteraction  tap/hold state machine → effects
  Catalog/                 ActionPresentation (titles, SF Symbols, permissions), ActionCatalog (library templates), DefaultRings
  Storage/ConfigFile       JSON load/save/backup/import/export
Sources/Halo/              the app (default actor isolation: MainActor)
  App/                     HaloApp (@main), AppDelegate, AppModel (single source of truth), SettingsRouter, WindowCoordinator, MenuBarContent
  Trigger/                 HotKeyCenter (Carbon hotkeys: press+release), KeyboardLayout (key labels)
  Overlay/                 OverlayController, OverlayPanel, ToastPresenter
  Ring/                    RingViewModel, RingMetrics (contracts) + RingView, shapes, themes (renderer)
  Actions/                 ActionRunner + executors, PermissionCenter
  Settings/                SettingsWindow (sidebar), Editor/ (ring editor, inspector, library), Panes/, Components/
  Onboarding/              first-run flow
  Support/                 ViewState, Logging, ColorPalette, AppCatalog, IconView, Feedback
Scripts/                   build-app.sh, make-icon.swift
Makefile                   build / app / run / install / test / clean
```

### Data flow
- `AppModel.shared.config` (a `HaloConfig` value) is the single source of truth. All edits go
  through `AppModel.update(_:_:)` / `updateRing` / `updateSettings` / `setSlot`, which register
  undo, debounce-save to `~/Library/Application Support/Halo/config.json`, and call
  `settingsDidChange(old, new)`.
- The overlay snapshots the resolved ring (`config.resolvedRing(forFrontmostBundleID:)`) when it
  opens; edits during a session apply next time.
- `RingViewModel` is what `RingView` draws. The overlay and the editor each own one.

### Conventions (all code)
- Write `@ViewState` instead of `@State` (see `Support/SwiftUICompat.swift`: the `@State` macro
  plugin is missing without Xcode). Never use `#Preview`, `@Entry`, `@Animatable`.
- The `Halo` target defaults to `@MainActor`. Mark pure helpers `nonisolated` when they must run off
  the main actor. C callbacks (Carbon, CGEvent) hop with `MainActor.assumeIsolated` when on main.
- No force unwraps on user data or system lookups. Fail soft, log with `Log.<category>`.
- Every interactive element has an accessibility label; honour Reduce Motion, Reduce
  Transparency and Increase Contrast; everything works in light and dark mode.
- Match the existing style: small focused types, doc comments on non-obvious API, no dead code.

---

## 2. Trigger and selection behaviour

Trigger: one global shortcut (default ⌃⇧⌘H, i.e. Control-Shift-Command-H), registered with Carbon `RegisterEventHotKey` so it
needs no permission and reports press and release. Users point a mouse button at it in Logi
Options+, BetterTouchTool, SteerMouse, etc. Recording a new trigger suspends the old one.

Selection modes (`AppSettings.selectionMode`), implemented by `RingInteraction` (tested):
- **auto** (default): press opens the ring at the pointer. Release with a slot highlighted runs it
  (also for very quick flicks: mark-ahead). Release in under `holdThreshold` (0.28 s) with nothing
  highlighted keeps the ring open (tap mode). Release after the threshold with nothing highlighted
  cancels.
- **tapThenClick**: release never runs anything; the ring stays open.
- **holdAndRelease**: release runs the highlight or cancels.
In every mode, while open: click a slot to run it; click the hub to go back (in a folder) or
close; click outside to close; press the trigger again to run the highlighted slot (or close if
none); `1`–`9`,`0` run slots directly; arrows move the highlight (jump toward the direction, then
walk around); Tab/⇧Tab cycle; Return/Space run the highlight; Esc goes back or closes; Delete goes
back. Empty slots can't be chosen (shake + "nope" haptic); releasing over one cancels.

Highlighting: pointer angle from the ring centre picks the slot (`RingGeometry`). Nothing is
highlighted inside `deadZoneRadius`. While the trigger is held, the target is unbounded (a flick
past the ring still counts). In tap mode, the pointer must be within `maxHitRadius`.

Folders (nested rings): choosing a folder slot replaces the ring in place with its ring (the hub
shows the folder's name and a back chevron); Esc/Delete/hub-click returns. Folders may nest.

Placement: centred on the pointer, clamped so the whole ring stays inside the visible frame of the
screen under the pointer (menu bar and Dock excluded), or centred on that screen
(`placement = .screenCenter`). Works on every display and Space, above full-screen apps.

Focus: the overlay never activates Halo. The frontmost app stays frontmost and keeps keyboard
focus, so synthesized shortcuts land there. Navigation keys are grabbed only while the ring is open
(temporary hotkeys) and released on close.

Running: on choose, the slot flashes (≈120 ms), the ring dismisses, and the action runs once the
overlay is gone. Failures and missing permissions show a small toast near the pointer, with an
"Open Settings" button for permissions.

App rings: if `appRingsEnabled` and the frontmost app has an enabled `AppProfile`, its ring
replaces the global ring; `inheritsGlobalSlots` fills its empty slots from the global ring. The hub
shows the app's icon when an app ring is active.

---

## 3. Actions

| Kind | What it does | Needs |
|---|---|---|
| app (open/toggle/quit) | launch or focus; toggle hides if frontmost; quit | – |
| url | open URL/deep link, optionally with a chosen browser | – |
| file | open file/folder, or reveal in Finder | – |
| keystroke | send a key combo to the frontmost app | Accessibility |
| media | play/pause, next, previous, volume ±, mute, brightness ± (system HUD) | Accessibility |
| screenshot | area / window / screen (file or clipboard), or the ⌘⇧5 toolbar | Screen Recording (not for toolbar) |
| system | Mission Control, App Windows, Show Desktop, Apps, Notification Center, Spotlight, Siri, Lock, Display Sleep, Sleep, Screen Saver, Emoji & Symbols, Dictation, Dark Mode, Do Not Disturb, Force Quit, System Settings | varies |
| edit | copy, cut, paste, paste plain, undo, redo, select all, find | Accessibility |
| window | halves, fill, centre, minimise, full screen, next display, close | Accessibility |
| shortcut | run an Apple Shortcut (optionally with the selection as input) | – |
| appleScript / shell | run a script | Automation (AppleScript) |
| text | paste (clipboard restored) or type a snippet; {date} {time} {clipboard} {selection} | Accessibility |
| aiPrompt | copy selection → fill `{selection}` in the prompt → open ChatGPT/Claude/Perplexity with it prefilled (Gemini/custom: copy prompt + open) | Accessibility when using the selection |
| folder | open a nested ring | – |
| macro | run steps in order with delays (Smart Action) | union of steps |

---

## 4. Configurator ("Halo Settings")

One window, `NavigationSplitView`:
- **Sidebar**: "Rings" section: *Everywhere* (global ring) then each app ring (app icon + name,
  toggle to enable, context menu: duplicate from global, remove), "+ Add App Ring…" (suggests
  frontmost/recent/running apps, then all installed apps with search). "Settings" section:
  General, Appearance, Permissions, About.
- **Ring editor** (detail for a ring):
  - Centre: a large live `RingView` (editor mode) with the real theme. Click a slot to select it.
    Hover shows its name in the hub. Drag a library item onto a slot to assign it (drop target
    glows). Drag one slot onto another to swap. Context menu per slot: Edit, Clear, Duplicate to
    next empty, Convert to Nested Ring, Move to… Delete/Backspace clears the selected slot; arrow
    keys move selection; ⌘Z/⇧⌘Z undo/redo; Return opens the inspector.
  - Breadcrumb above the canvas for nested rings (Everywhere › Windows); double-click a folder slot
    to enter it.
  - Toolbar: slot count (4–12) stepper/segmented, theme switch (Classic/Glass), "Try It" (opens
    the real overlay at screen centre), app-ring options (enabled, inherit empty slots).
  - **Inspector** (trailing): for the selected slot: action type menu (grouped by category), the
    per-kind editor (app picker with search, URL field + browser picker, file chooser, shortcut
    recorder, media/system/edit/window pickers with icons, Shortcuts list from `shortcuts list`,
    script editor with monospaced text and a "Run Now" test, snippet editor with placeholder chips,
    AI prompt editor with service picker and `{selection}` chip, macro step list with add/reorder/
    delay), then Label (placeholder shows default), Icon (default / SF Symbol picker with search /
    app icon / emoji / image file), Tint (palette + custom), and a permission note if needed.
  - **Action library** (sheet or leading panel): search field, category chips, grid/list of
    templates with icons and subtitles; drag to the ring or double-click to assign to the selected
    slot. Installed apps appear under Apps.
- **General**: trigger shortcut recorder (+ how-to for Logi Options+ / BetterTouchTool), selection
  mode (with a one-line explanation each), hold threshold slider, placement, app rings toggle,
  launch at login, show menu bar icon, import/export/reset.
- **Appearance**: theme cards with live previews, ring size slider, labels (hub/always/none),
  slot numbers, accent colour, animation speed, haptics, sounds.
- **Permissions**: one row per permission: status badge, why it's needed, Grant/Open Settings
  button; refreshes when the window becomes key.
- **About**: icon, version, short credits, link to config folder.

Onboarding (first launch, also from the menu): Welcome (animated ring) → Trigger (record or keep
default; how to map a mouse button) → Permissions (Accessibility, optional Screen Recording) →
Try it (live ring) → Done.

Menu bar extra (template icon): Show Ring, Open Halo Settings…, Pause Halo, Help/Onboarding, Quit.

---

## 5. Decisions from research (binding)

Research notes (detailed, with sources) are in the session scratchpad `research-out/*.md`; this
section is the distilled decision list.

### Overlay window (overlay-runtime)
- App runs with activation policy `.accessory` (LSUIElement) — required to float over other apps'
  full-screen Spaces.
- One pre-warmed `NSPanel` subclass created at launch: styleMask `[.borderless, .nonactivatingPanel]`
  (set at init); `isFloatingPanel = true` then `level = .screenSaver`; collectionBehavior
  `[.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle]`;
  `hidesOnDeactivate = false`; `isOpaque = false`; `backgroundColor = .clear`; `hasShadow = false`
  (shadows drawn in SwiftUI); `animationBehavior = .none`; `isMovable = false`;
  `isReleasedWhenClosed = false`; `ignoresMouseEvents = false`; `canBecomeKey`/`canBecomeMain`
  return false. Show with `setFrame(_:display: false)` + `orderFrontRegardless()`; never activate.
- Panel is tight: `RingMetrics.canvasSide` square centred on the ring centre. Hosting view is an
  `NSHostingView` subclass with `acceptsFirstMouse = true`, `sizingOptions = []`,
  `safeAreaRegions = []`. Root view sets `.environment(\.appearsActive, true)` so glass renders as
  active in a non-key panel.
- Pointer: poll `NSEvent.mouseLocation` from a display link (`NSView.displayLink(target:selector:)`,
  plain `@objc` selector) while open. Vector from the ring centre → slot with
  `RingGeometry.slot(dx:dy:deadZone:maxRadius:current:hysteresis:)`; y must be flipped (AppKit is
  y-up, RingGeometry is y-down). Holding: dead zone `holdDeadZone`, unbounded. Tap mode: dead zone
  `tapDeadZone` (= hub), bounded by `maxHitRadius`. Hover dwell ≥ 0.35 s on a folder while holding
  → `interaction.dwell(on:)`.
- Clicks: decided by geometry on mouseUp in the panel's `sendEvent`; click-outside via a global
  `.leftMouseDown/.rightMouseDown` monitor (the click passes through to the app underneath) → close.
  Right-click inside the ring = close. ⌘-click on a slot = open the configurator at that slot.
- Scroll wheel over the ring while a volume/brightness slot is highlighted adjusts it (one media
  key per scroll notch, accumulated deltas), like Logitech's adjustable bubbles; the ring stays open.
- Keys while open: temporary Carbon hot keys (no permission, no focus change) for Esc, Return,
  Space, Tab, ⇧Tab, Delete, arrows, digits 0–9 and numpad (numpad maps by direction: 8 N, 9 NE,
  6 E, 3 SE, 2 S, 1 SW, 4 W, 7 NW, 5 = confirm). Unregistered on every dismissal path.
- Dismiss also on: `activeSpaceDidChange`, `didActivateApplication` (other than at open),
  `didChangeScreenParametersNotification`, `screensDidSleep`, `sessionDidResignActive`.
  No idle auto-dismiss (accessibility), but a watchdog guarantees navigation keys are released
  whenever the panel is hidden.
- Missed key-up fallback: while holding, if the trigger's modifiers read as released in
  `CGEventSource.flagsState(.combinedSessionState)` for > 0.15 s without a Carbon release event,
  synthesize `triggerUp`.
- Placement: inclusive hit-test of `NSScreen.screens` for the pointer (not `NSScreen.main`),
  clamp the ring (canvas) into `visibleFrame` minus `safeAreaInsets.top`, 8 pt margin,
  `backingAlignedRect`. When clamped, angles are computed from the ring's real centre (no warp).
- VoiceOver: post an announcement with the highlighted slot's title on change.

### Running actions (actions)
- Record `NSWorkspace.shared.frontmostApplication` when the trigger fires.
- Before posting synthetic keys, wait (≤ 300 ms) until the trigger's modifiers are released
  (`CGEventSource.flagsState(.combinedSessionState)`), then post with explicit flags.
- Actions run after the panel is ordered out (the fade can overlap since the panel never had focus).
- Confirmation HUD (`settings.showConfirmations`): after actions without visible effect (copy,
  cut, media, dark mode, DND, text paste, shortcut/script success) show a ~0.6 s toast with the
  slot's icon and title.

### Configurator windows (configurator-shell)
- AppKit-managed `NSWindow` + `NSHostingController` (`sceneBridgingOptions = [.toolbars, .title]`),
  not the SwiftUI `Settings` scene (unreliable from LSUIElement apps). Switch activation policy to
  `.regular` while the settings window is open (Dock icon, ⌘-Tab), back to `.accessory` on close.
  `NavigationSplitView` + `.inspector` + `Form { }.formStyle(.grouped)`; `.windowToolbarStyle(.unified)`.
- Menu bar: SwiftUI `MenuBarExtra` (`.menu` style), `isInserted` bound to `showMenuBarIcon`;
  every item `Label(...).labelStyle(.titleAndIcon)` (macOS 27 hides menu icons otherwise).
- Haptics only fire on Force Touch trackpads (`.alignment`, `.levelChange`); say so in Appearance.
- Symbol picker: read SF Symbols names/categories/search keywords at runtime from
  `/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/*.plist` (name_availability,
  categories, symbol_categories, symbol_search), validate with `NSImage(systemSymbolName:)`, fall
  back to a curated list.
- Drag and drop: library rows `.draggable(...)` with a custom Transferable (template id as
  string payload is fine); ONE `.dropDestination` on the ring canvas, slot resolved from the drop
  location with `RingGeometry`; `onDropSessionUpdated` (or equivalent) updates
  `RingViewModel.dropTarget`.
- Trigger recorder: pauses the global trigger while recording; local monitor for keyDown +
  flagsChanged with live ⌃⌥⇧⌘ glyphs; Esc cancels, Delete clears. Accept only combos with ⌘, ⌃ or
  ⌥ (⇧ alone isn't enough) or bare F1–F20. Warn on ⌥-only / ⌥⇧-only, on a deny list (⌘Tab, ⌘Space,
  ⌘Q/W/H/M/C/V/X/Z, ⇧⌘3/4/5, ⌥⌘Esc, ⌃⌘Q, ⌃Return) and when registration fails (shortcut in use).
- "Test your trigger" calibration (General pane): user holds their mouse button ~1 s; measure
  press→release time and report whether hold-and-release works with their mouse software.

## 6. Visual and motion design

Sizes come from `RingMetrics` (Medium = scale 1.0; the user's size slider scales everything).
Folder behaviour in the live overlay is Logitech's: opening a folder keeps the root ring visible
(dimmed, inactive except for clicks) and fans the folder's children out on an outer circle at
`folderRadius`, `childStep` (22.5°) apart, centred on the folder's direction
(`RingViewModel.childArc`, `slotOffset`). Deeper folders replace the children on that arc. The
editor always shows one level at a time. Hit-testing for overlay and editor is
`RingViewModel.hitTest` (overlay) / `RingGeometry` (editor) — the renderer only draws.

### Classic theme (Logitech-exact look, with legibility fixes)
- **Bubbles**: 46 pt circles on radius 82.5 pt around the hub, slot 0 at 12 o'clock, clockwise.
  Idle fill: light grey `rgb(243,241,241)` at ~0.90 opacity (Logitech's macOS fill is ~0.38 and
  reviewers find it illegible), a hairline `black @ 8%` stroke and a very soft shadow
  (`black @ 12%`, radius 6, y 2) so bubbles read on white backgrounds. No blur.
- **Glyphs**: SF Symbols at 20 pt, weight medium, near-black (`#1D1D1F`), monochrome. App icons
  37 pt (no bubble fill shows behind them; when highlighted they sit on a dark disc). Emoji at
  ~22 pt. Custom images clipped to a circle.
- **Highlight**: the bubble's fill cross-fades to its tile colour (slot tint, default solid near-
  black `#111`) and the glyph to white, ~0.22 s ease-in-out, no scale change. With Increase
  Contrast or Differentiate Without Colour add a 2 pt accent outline.
- **Hub**: 31 pt disc, grey ~52% (`rgb(130,130,135)` at 0.55) with a white `xmark` 12 pt; when the
  pointer is over the hub (tap mode) it turns pale red (`systemRed` @ 0.30, xmark red). Inside a
  folder the hub shows `chevron.backward`. App rings: a 14 pt app-icon badge at the hub's lower
  right.
- **Labels** (`labelMode`): `.hub` (default, "On hover") = Logitech's tooltip: a near-white
  capsule (`rgb(250,250,250)` 0.96, 20 pt tall, 10 pt radius, 8 pt horizontal padding, 11 pt
  medium `#1D1D1F` text, subtle shadow) with a small notch pointing at the bubble, placed radially
  outward 6 pt beyond the highlighted bubble; it appears with the highlight (0.12 s fade).
  `.always` = every bubble gets a small caption chip outward; `.none` = icons only.
- **Folders**: a folder bubble carries an outward "tab": a 14 pt circle fused to its outer edge
  (metaball-like; draw it as a union of two circles) holding a tiny `ellipsis` or arc glyph. When
  open the folder bubble fills with its tile colour; children appear on the outer circle with the
  same bubble style, fanning out from the folder bubble (scale 0.6→1 + fade, 25 ms stagger from
  the centre child outward). The root ring dims to 55% while fanned.
- **Adjustable slots** (media volume/brightness): a 5 pt dot on the bubble's outer edge.
- **Slot numbers** (`showNumbers`): a 12 pt grey number badge on each bubble's inner edge.
- **Empty slots**: dashed 1.5 pt outline circle, transparent fill, faint `plus` glyph (live mode:
  just the faint dashed circle).

### Glass theme (native macOS 26+ Liquid Glass)
- One `GlassEffectContainer` holding N annular-sector shapes (outer 140 pt, inner 0.42×outer,
  4 pt gaps, 8 pt corner radius via the inset-sector ∪ round-joined-stroke construction) each with
  `.glassEffect(.regular.tint(highlighted ? accent.opacity(0.45) : nil).interactive(), in: shape)`,
  plus a glass hub circle (radius `hubRadius`). Never glass behind glass; glassEffect last.
- Glyphs 24 pt `.hierarchical`, primary colour; highlighted: white glyph, segment tinted with the
  slot tint or the accent, scale 1.05, `.symbolEffect(.bounce.up.byLayer, value: highlighted)`.
- Hub shows the highlighted slot's title (12.5 pt semibold, `.contentTransition(.opacity)` /
  blur-replace), or the app badge + "Close" hint when nothing is highlighted; back chevron in
  folders.
- Folders fan out as an outer partial band (sectors of `childStep`) with the same glass style.
- Reduce Transparency: `Glass.identity` + solid `windowBackgroundColor` fills with hairline borders.

### Motion (both themes; durations ÷ animationSpeed; 0 = no animation)
- **Appear**: whole ring scales 0.15 → 1.0 about its centre with opacity 0 → 1, curve
  `timingCurve(0.16, 1, 0.3, 1, duration: 0.42)` (measured exponential ease-out, settles ~0.3 s), no
  overshoot, no stagger (Classic). Glass: hub then segments via
  `glassEffectTransition(.matchedGeometry)` inside `.bouncy(duration: 0.35, extraBounce: 0.05)`.
  Input is never blocked by animation (a highlight during the appear jumps straight to state).
- **Highlight**: 0.22 s ease-in-out cross-fade (Classic); `.snappy(duration: 0.18)` (Glass).
- **Execute**: the chosen slot flashes (brief brighten/scale 1.08 pulse, ~0.1 s), then dismiss.
- **Dismiss**: ease-in 0.15 s to scale 0.45 + fade (Classic); Glass: `.smooth(duration: 0.2)`
  scale 1.04 + fade on execute, `.snappy(duration: 0.16)` scale 0.92 + fade on cancel.
- **Reject** (empty slot): horizontal shake (3 oscillations, 6 pt, 0.3 s).
- **Folder open/close**: children fan out/in (see Classic), root dims; pop reverses.
- **Editor mode**: on first appearance bubbles build clockwise from 12 o'clock (hub first, 33 ms
  stagger, ~0.35 s); selection = 2.5 pt accent ring around the slot + subtle lift; drop target =
  accent glow + scale 1.08; hover = the Classic/Glass highlight at 60% strength.
- **Reduce Motion**: cross-fades only (0.15 s), no scaling, `symbolEffectsRemoved()`.

---

## 7. Changes since the first spec (these win over earlier sections)

- **Hover opens folders** after `RingMotion.folderDwell` (~0.13 s) in tap and hold modes; hovering
  another root slot while a folder is fanned out switches to it; clicking the open folder's own
  slot keeps it open. Leaving a folder while holding keeps the hold.
- **Gaps close** (`AppSettings.closesGaps`, default on): live rings show only filled slots, evenly
  spread (`Ring.compacted()`); the editor still shows every slot.
- **Motion**: the live Classic ring is drawn with Core Animation (`Ring/Layers/`): hub, then a
  clockwise one-after-another bloom (~28 ms apart, spring 0.25 s / 0.72), 0.16 s critically damped
  dismiss. Glass grows its glass shapes (never scales or fades glass) with the same cascade.
- **Overlay input**: the panel ignores mouse events outside the ring's interactive area so clicks
  reach the app below; hold strokes are measured from the press point.
- **In-app actions**: `.appShortcut` (an app's own shortcut, optionally bring forward and return)
  and `.menuItem` (a menu-bar command by path, read live through Accessibility), with curated
  presets in `AppActionPresets` (generated by `docs/tools/gen-app-actions.py` with
  `docs/app-actions.json`), plus `.clickButtons` (controls clicked in order by accessible name,
  each step with alternative names and an optional flag; `Actions/ButtonActions.swift`), used for
  Teams' Start Recording / Start Transcription, which have no shortcut.
- **Updates**: `Updates/UpdateController` checks GitHub Releases daily; the update zip is verified
  against its SHA-256, bundle identifier, version and code signature before replacing the app.
- **Signing**: ad-hoc builds carry the designated requirement `identifier "com.srinidhibhat.Halo"`
  so privacy grants survive rebuilds and updates; Permissions offers **Fix Access** to clear a stale
  grant.
- **Accessibility calls** go through `Background.runAX(pid:…)`: on the main actor for Halo's own
  windows (AppKit answers those in-process), in the background with a timeout otherwise.
