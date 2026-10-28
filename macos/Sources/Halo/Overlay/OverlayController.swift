import AppKit
import HaloCore

/// Shows the ring at the pointer, runs the input state machine, and runs chosen actions.
///
/// The ring lives in one pre-warmed `OverlayPanel` that never becomes key: the frontmost app
/// keeps keyboard focus, so synthesized shortcuts land there. While the ring is open the
/// controller polls the pointer every frame, grabs navigation keys as temporary hot keys and
/// watches for clicks elsewhere. The panel takes mouse events only over the ring itself, so
/// clicks and scrolls on its transparent canvas reach the app below. Resting the pointer on a
/// folder opens it, like a submenu, whether or not the trigger is held. Input goes through
/// `RingInteraction` (tap / hold behaviour) and its effects are applied here. Every way of
/// closing releases keys, polling and monitors through `releaseSession()`, and a watchdog
/// catches anything that slips through.
final class OverlayController {
    static let shared = OverlayController()

    /// True while the ring is open and accepting input (until it starts to dismiss).
    private(set) var isShowing = false

    /// While set, trigger presses don't open the ring: each press→release reports how long the
    /// trigger was held (seconds). Used by the "Test your trigger" calibration.
    var calibration: ((TimeInterval) -> Void)? {
        didSet {
            calibrationPressedAt = nil
            if calibration != nil { dismiss() }
        }
    }

    private enum Timing {
        /// App activations this soon after opening are side effects of the trigger, not a switch.
        static let activationGrace: TimeInterval = 0.3
        static let watchdog: TimeInterval = 0.5
    }

    /// Posted when the screen locks (no workspace notification covers it).
    private static let screenLocked = Notification.Name("com.apple.screenIsLocked")

    private let model: RingViewModel
    private var interaction: RingInteraction
    /// Settings as of the last time the ring opened (or changed while it was closed).
    private var settings: AppSettings
    private var session: RingSession?
    /// Bumped whenever a session begins, so delayed work from an earlier one can tell it's stale.
    private var generation = 0
    /// True during the chosen slot's flash: the session is over, but the ring is still up.
    private var isFlashing = false
    private var hideTask: Task<Void, Never>?
    /// The panel is on screen in its collapsed state; the next frame starts the appear animation.
    private var appearPending = false
    private var started = false

    private var lastPointer: CGPoint?
    /// While holding: the pointer has left the dead zone around the press point, so it drives
    /// the highlight.
    private var holdStrokeStarted = false
    /// The folder slot the pointer moved onto, and since when (`HotKeyCenter.now`).
    private var dwell: (slot: Int, since: TimeInterval)?
    private var scrollStepper = ScrollStepper()
    /// The mouse button that went down inside the ring; a mouse-up without one is ignored.
    private var buttonDownInRing: NSEvent.EventType?
    private var calibrationPressedAt: TimeInterval?
    private var mouseMonitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var watchdog: Timer?

    private lazy var panel = makePanel()
    private lazy var tracker = PointerTracker { [weak self] in self?.tick() }

    private init() {
        let config = AppModel.shared.config
        settings = config.settings
        model = RingViewModel(mode: .live, ring: config.globalRing, settings: config.settings)
        interaction = RingInteraction(mode: config.settings.selectionMode, holdThreshold: config.settings.holdThreshold)
    }

    // MARK: Lifecycle

    /// Wire-up: registers the trigger from settings, installs the dismissal observers and
    /// pre-warms the panel. Called once at launch.
    func start() {
        guard !started else { return }
        started = true
        settings = AppModel.shared.settings
        applyInteractionSettings()
        registerTrigger()
        observeSystemEvents()
        prewarm()
    }

    /// Re-reads settings: re-registers the trigger when it changed (or never registered) and
    /// updates the selection mode and appearance for the next presentation.
    func settingsChanged(_ settings: AppSettings) {
        let previous = self.settings
        self.settings = settings
        if started, settings.trigger != previous.trigger || (settings.trigger != nil && HotKeyCenter.shared.registeredTrigger == nil) {
            registerTrigger()
        }
        if !interaction.isOpen { applyInteractionSettings() }
        if session == nil { model.apply(settings) }
    }

    private func registerTrigger() {
        HotKeyCenter.shared.setTrigger(settings.trigger,
                                       onDown: { [weak self] time in self?.triggerDown(at: time) },
                                       onUp: { [weak self] time in self?.triggerUp(at: time) })
    }

    private func applyInteractionSettings() {
        interaction.mode = settings.selectionMode
        interaction.holdThreshold = settings.holdThreshold
    }

    private func makePanel() -> OverlayPanel {
        let panel = OverlayPanel()
        // Classic: the Core Animation ring; Glass: SwiftUI. Switches with the theme setting.
        panel.contentView = OverlayRingContentView(model: model)
        panel.interceptor = { [weak self] event in self?.handlePanelEvent(event) ?? false }
        // Clicks pass through until a ring is up (see `updateMouseRegion`).
        panel.ignoresMouseEvents = true
        return panel
    }

    /// Creates the window and renders the ring once off screen, so the first real open is instant.
    private func prewarm() {
        let side = model.metrics.canvasSide
        panel.setFrame(CGRect(x: -20_000, y: -20_000, width: side, height: side), display: false)
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    // MARK: Trigger

    /// Trigger callbacks (from HotKeyCenter).
    func triggerDown(at time: TimeInterval) {
        guard !HotKeyCenter.shared.isSuspended else { return }
        if calibration != nil {
            calibrationPressedAt = time
            return
        }
        guard !isFlashing else { return }
        if interaction.isOpen {
            // Second press: run what is highlighted, or close.
            updatePointer()
            perform(interaction.triggerDown(at: time))
            return
        }
        guard !AppModel.shared.isPaused else { return }
        openAtPointer(at: time)
    }

    func triggerUp(at time: TimeInterval) {
        if let calibration {
            if let pressedAt = calibrationPressedAt { calibration(max(0, time - pressedAt)) }
            calibrationPressedAt = nil
            return
        }
        guard interaction.isOpen else { return }
        // A flick released before the next frame still counts (mark-ahead).
        updatePointer()
        let wasHolding = interaction.isHolding
        perform(interaction.triggerUp(at: time))
        // Now in tap mode: the pointer points from the ring's centre, within the hub dead zone
        // and the outer bound.
        if wasHolding, interaction.phase == .open { updatePointer(force: true) }
    }

    // MARK: Presenting

    /// Opens the ring at the centre of the screen under the pointer in tap mode (configurator "Try It").
    func presentForTesting() {
        presentForTesting(target: .global)
    }

    /// Same, for a specific ring (the editor's "Try It" on an app ring), even if it is disabled.
    func presentForTesting(target: RingTarget) {
        dismiss()
        guard !isFlashing else { return }
        let config = AppModel.shared.config
        let resolved: ResolvedRing
        switch target {
        case .global:
            resolved = ResolvedRing(ring: config.globalRing, profile: nil)
        case .app(let id):
            guard let index = config.profileIndex(id: id) else {
                Log.overlay.error("Try It: no app ring with id \(id, privacy: .public)")
                return
            }
            var preview = config
            preview.settings.appRingsEnabled = true
            preview.appProfiles[index].isEnabled = true
            resolved = preview.resolvedRing(forFrontmostBundleID: preview.appProfiles[index].bundleID)
        }
        settings = AppModel.shared.settings
        let now = HotKeyCenter.now
        guard beginSession(resolved, frontmostApp: NSWorkspace.shared.frontmostApplication, centeredOnScreen: true, at: now) else { return }
        // A press and an instant release in tap-then-click mode leave the ring open.
        interaction.mode = .tapThenClick
        perform(interaction.triggerDown(at: now))
        perform(interaction.triggerUp(at: now))
        applyInteractionSettings()
    }

    private func openAtPointer(at time: TimeInterval) {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let config = AppModel.shared.config
        settings = config.settings
        applyInteractionSettings()
        let resolved = config.resolvedRing(forFrontmostBundleID: frontmost?.bundleIdentifier)
        guard beginSession(resolved, frontmostApp: frontmost, centeredOnScreen: settings.placement == .screenCenter, at: time) else { return }
        perform(interaction.triggerDown(at: time))
    }

    /// Prepares a session (placement, view model) for the `.show` effect to present.
    private func beginSession(_ resolved: ResolvedRing, frontmostApp: NSRunningApplication?, centeredOnScreen: Bool, at time: TimeInterval) -> Bool {
        let pointer = NSEvent.mouseLocation
        guard let screen = OverlayPlacement.screen(containing: pointer) else {
            Log.overlay.error("No screen to show the ring on")
            return false
        }
        // Reopened while the last ring fades out: it stays up and grows back from where it is.
        hideTask?.cancel()
        hideTask = nil
        generation += 1

        model.apply(settings)
        model.breadcrumb = []
        model.appBadge = resolved.profile.map { RingViewModel.AppBadge(bundleID: $0.bundleID, name: $0.appName) }
        model.executing = nil
        model.rejected = nil
        model.isHolding = false
        model.isHubHovered = false

        // Keep the ring itself (plus tooltip room) on screen; the transparent canvas around it,
        // sized for fanned-out folders of the largest level, may extend past the screen edge.
        let rootMetrics = RingMetrics(theme: settings.theme, scale: settings.ringScale, slotCount: resolved.ring.slotCount)
        let slotCount = RingSession.largestSlotCount(in: resolved.ring)
        let side = RingMetrics(theme: settings.theme, scale: settings.ringScale, slotCount: slotCount).canvasSide
        let usable = OverlayPlacement.usableFrame(of: screen)
        let requested = centeredOnScreen ? CGPoint(x: usable.midX, y: usable.midY) : pointer
        let keep = rootMetrics.clampRadius * 2
        let kept = OverlayPlacement.frame(size: CGSize(width: keep, height: keep), centeredOn: requested, on: screen)
        let frame = screen.backingAlignedRect(CGRect(x: kept.midX - side / 2, y: kept.midY - side / 2, width: side, height: side),
                                              options: .alignAllEdgesNearest)
        session = RingSession(root: resolved.ring,
                              closesGaps: settings.closesGaps,
                              target: resolved.profile.map { .app($0.id) } ?? .global,
                              profileRing: resolved.profile?.ring,
                              title: resolved.profile?.appName ?? "Halo",
                              frontmostApp: frontmostApp,
                              frame: frame,
                              pressPoint: pointer,
                              openedAt: time)
        // Shown as the session sees it: with gaps closed, only the filled slots.
        model.showLevel(session?.root ?? resolved.ring, transition: .none)
        return true
    }

    /// The `.show` effect: puts the prepared session on screen and starts listening.
    private func presentSession() {
        guard let session else { return }
        ToastPresenter.shared.dismiss()
        interaction.setLevel(RingSession.kinds(of: session.root))
        let isFadingOut = panel.isVisible
        panel.setFrame(session.frame, display: false)
        if isFadingOut {
            // The renderer's springs carry on from the current, partly dismissed state.
            model.isPresented = true
        } else {
            // On screen collapsed first, then grow on the next frame, so the appear always
            // starts from collapsed.
            model.isPresented = false
            panel.contentView?.layoutSubtreeIfNeeded()
            panel.orderFrontRegardless()
            appearPending = true
        }
        isShowing = true

        // The pointer drives the highlight once it moves from here; keys can take over meanwhile.
        lastPointer = NSEvent.mouseLocation
        holdStrokeStarted = false
        dwell = nil
        scrollStepper.reset()
        buttonDownInRing = nil
        updateMouseRegion()
        tracker.start(in: panel)
        HotKeyCenter.shared.beginNavigation { [weak self] key in self?.handle(key) }
        installMouseMonitors()
        startWatchdog()

        Feedback.play(.open)
        OverlayAnnouncer.announce("\(session.title) ring")
    }

    // MARK: Effects

    private func perform(_ effects: [RingInteraction.Effect]) {
        for effect in effects {
            switch effect {
            case .show: presentSession()
            case .dismiss: endSession()
            case .highlight(let index): highlight(index)
            case .execute(let index): run(index)
            case .enterFolder(let index): enterFolder(index)
            case .exitFolder: exitFolder()
            case .reject(let index): reject(index)
            }
        }
        if session != nil { model.isHolding = interaction.isHolding }
    }

    private func highlight(_ index: Int?) {
        dwell = nil
        scrollStepper.reset()
        guard model.highlighted != index else { return }
        model.highlighted = index
        guard let index, let slot = session?.slot(at: index) else { return }
        Feedback.play(.highlight)
        OverlayAnnouncer.announce(slot.isEmpty ? "Empty" : slot.displayTitle)
    }

    private func enterFolder(_ index: Int) {
        guard let inner = session?.enterFolder(at: index) else {
            Log.overlay.error("Enter folder: slot \(index) is not a folder")
            dismiss()
            return
        }
        showLevel(inner, transition: .push(fromSlot: index))
        Feedback.play(.open)
        OverlayAnnouncer.announce(session?.breadcrumb.last ?? "Folder")
    }

    private func exitFolder() {
        guard let parent = session?.exitFolder() else { return }
        showLevel(parent.ring, transition: .pop(toSlot: parent.folderSlot))
        OverlayAnnouncer.announce(session?.breadcrumb.last ?? "\(session?.title ?? "Halo") ring")
    }

    private func showLevel(_ ring: Ring, transition: RingViewModel.LevelTransition) {
        model.showLevel(ring, transition: transition)
        model.breadcrumb = session?.breadcrumb ?? []
        interaction.setLevel(RingSession.kinds(of: ring))
        dwell = nil
        // The new level highlights from the pointer only once it moves: releasing right after a
        // dwell-open must not run whatever happens to lie in that direction.
        lastPointer = NSEvent.mouseLocation
    }

    private func reject(_ index: Int) {
        model.reject(index)
        Feedback.play(.reject)
        OverlayAnnouncer.announce("Empty slot")
    }

    /// The `.execute` effect: flash the slot, dismiss, and run the action. The panel never had
    /// focus, so the action can start while the ring fades out, unless it captures the screen.
    private func run(_ index: Int) {
        guard let ended = releaseSession() else { return }
        guard let slot = ended.slot(at: index), let action = slot.action, !action.isFolder else {
            hidePanel()
            return
        }
        model.executing = index
        Feedback.play(.select)
        isFlashing = true
        let flash = RingMotion.flashDuration(speed: settings.animationSpeed, reduceMotion: reduceMotion)
        let token = generation
        Task { [weak self] in
            if flash > 0 { try? await Task.sleep(for: .seconds(flash)) }
            guard let self else { return }
            self.isFlashing = false
            if self.generation == token { self.hidePanel() }
            if Self.capturesScreen(action) { await self.waitUntilPanelHidden() }
            let context = ActionContext(frontmostApp: ended.frontmostApp, slotTitle: slot.displayTitle, ringCenter: ended.center)
            Log.overlay.info("Running \(action.kind.rawValue, privacy: .public) from slot \(index)")
            let outcome = await ActionRunner.shared.run(action, context: context)
            ActionFeedback.present(outcome, slot: slot, action: action, anchor: ended.center)
        }
    }

    /// True for actions that take a screenshot, directly or as a Smart Action step: they must not
    /// capture the fading ring. (The toolbar captures later, once the user picks a mode.)
    private static func capturesScreen(_ action: Action) -> Bool {
        switch action {
        case .screenshot(let options): options.mode != .toolbar
        case .macro(let macro): macro.steps.contains { capturesScreen($0.action) }
        default: false
        }
    }

    /// Waits until the panel is off screen, plus a moment for the window server to drop it; at
    /// most half a second longer than the dismiss animation (the ring may have been reopened).
    private func waitUntilPanelHidden() async {
        let deadline = ContinuousClock.now + .seconds(RingMotion.dismissDuration(speed: settings.animationSpeed) + 0.5)
        while panel.isVisible, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        try? await Task.sleep(for: .milliseconds(30))
    }

    // MARK: Closing

    /// Closes the ring without running anything.
    func dismiss() {
        let effects = interaction.cancel()   // also resets a machine left open without a session
        guard session != nil else { return }
        if effects.isEmpty { endSession() } else { perform(effects) }
    }

    /// The `.dismiss` effect.
    private func endSession() {
        guard releaseSession() != nil else { return }
        hidePanel()
    }

    /// Ends the session's input: navigation keys, pointer polling and mouse monitors; clicks pass
    /// through the panel from now on. Returns the session that ended, or nil if none was open (so
    /// nothing runs twice).
    private func releaseSession() -> RingSession? {
        HotKeyCenter.shared.endNavigation()
        tracker.stop()
        removeMouseMonitors()
        panel.ignoresMouseEvents = true
        appearPending = false
        holdStrokeStarted = false
        dwell = nil
        lastPointer = nil
        buttonDownInRing = nil
        isShowing = false
        model.isHolding = false
        defer { session = nil }
        return session
    }

    /// Plays the dismiss animation, then orders the panel out.
    private func hidePanel() {
        model.isPresented = false
        hideTask?.cancel()
        let delay = RingMotion.dismissDuration(speed: settings.animationSpeed)
        let token = generation
        hideTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, let self, self.generation == token else { return }
            self.panel.orderOut(nil)
            self.hideTask = nil
        }
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    // MARK: Pointer

    private func tick() {
        guard session != nil else {
            tracker.stop()
            return
        }
        if appearPending {
            appearPending = false
            model.isPresented = true
        }
        updatePointer()
        updateMouseRegion()
        checkDwell()
    }

    /// Feeds what the pointer is over to the state machine when the pointer has moved (or when
    /// `force`d), so a highlight set from the keyboard sticks until the mouse moves.
    private func updatePointer(force: Bool = false) {
        guard let session, interaction.isOpen else { return }
        let pointer = NSEvent.mouseLocation
        if !force, let last = lastPointer, hypot(pointer.x - last.x, pointer.y - last.y) < 1 { return }
        lastPointer = pointer
        // In tap mode the pointer picks what is drawn under it, measured from the ring's centre.
        // While holding, strokes count from where the trigger went down (the same place unless
        // the ring was centred on the screen or kept clear of an edge), and only once the pointer
        // has left the dead zone there: a jitter during a quick tap must not pick the slot it
        // happens to face. The hold target is unbounded (a flick past the ring still counts).
        let holding = interaction.isHolding
        var origin = session.center
        if holding {
            origin = session.pressPoint
            if !holdStrokeStarted {
                guard hypot(pointer.x - origin.x, pointer.y - origin.y) >= model.metrics.holdDeadZone else { return }
                holdStrokeStarted = true
            }
        }
        // AppKit is y-up, the ring maths y-down. Fanned-out folder children are hit-tested on their arc.
        let hit = model.hitTest(dx: Double(pointer.x - origin.x),
                                dy: Double(origin.y - pointer.y),
                                holding: holding,
                                current: interaction.highlighted)
        let overHub = hit == .hub
        if model.isHubHovered != overHub { model.isHubHovered = overHub }
        switch hit {
        case .slot(let index): perform(interaction.pointerMoved(toSlot: index))
        case .rootSlot(let rootIndex): hoverRootSlot(rootIndex)
        case .hub, .none: perform(interaction.pointerMoved(toSlot: nil))
        }
        // A folder only opens once the pointer has moved onto it, not because it lay under a
        // resting pointer when the ring opened or the trigger came up.
        if !force { startDwell() }
    }

    /// The pointer is over the dimmed root ring while a folder is fanned out. Over the open
    /// folder's own slot the folder stays open with no child highlighted. Over any other root
    /// slot the folder closes and that slot highlights, like moving along a menu bar; a folder
    /// there opens in turn after the dwell.
    private func hoverRootSlot(_ rootIndex: Int) {
        guard model.folderAnchor != rootIndex else {
            perform(interaction.pointerMoved(toSlot: nil))
            return
        }
        returnToRoot()
        guard interaction.isOpen else { return }
        perform(interaction.pointerMoved(toSlot: rootIndex))
    }

    /// Closes every open folder, back to the root ring.
    private func returnToRoot() {
        while interaction.depth > 0, interaction.isOpen {
            perform(interaction.back())
        }
    }

    /// Starts timing the highlighted slot if it is a folder the pointer just moved onto.
    private func startDwell() {
        guard let index = interaction.highlighted, dwell?.slot != index,
              session?.slot(at: index)?.action?.isFolder == true else { return }
        dwell = (index, HotKeyCenter.now)
    }

    /// Opens the folder the pointer has rested on for `RingMotion.folderDwell`, in tap and hold
    /// modes alike.
    private func checkDwell() {
        guard let dwell else { return }
        guard interaction.highlighted == dwell.slot else {
            self.dwell = nil
            return
        }
        guard HotKeyCenter.now - dwell.since >= RingMotion.folderDwell else { return }
        self.dwell = nil
        perform(interaction.dwell(on: dwell.slot))
    }

    /// The panel takes mouse events only while the pointer is over something a click there would
    /// hit (or while a button that went down there is held). Clicks and scrolls on the rest of the
    /// transparent canvas reach the app below, and the global monitor closes the ring.
    private func updateMouseRegion() {
        guard let session else { return }
        let pointer = NSEvent.mouseLocation
        let hit = model.hitTest(dx: Double(pointer.x - session.center.x),
                                dy: Double(session.center.y - pointer.y),
                                holding: false,
                                current: nil)
        let ignores = hit == .none && buttonDownInRing == nil
        if panel.ignoresMouseEvents != ignores { panel.ignoresMouseEvents = ignores }
    }

    // MARK: Mouse

    /// Clicks are decided by geometry on mouse-up; nothing reaches SwiftUI.
    private func handlePanelEvent(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            buttonDownInRing = event.type
            return true
        case .leftMouseUp:
            if buttonDownInRing == .leftMouseDown {
                click(at: panel.convertPoint(toScreen: event.locationInWindow), modifiers: event.modifierFlags)
            }
            buttonDownInRing = nil
            return true
        case .rightMouseUp:
            // Right-click inside the ring closes it.
            if buttonDownInRing == .rightMouseDown { dismiss() }
            buttonDownInRing = nil
            return true
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDown, .otherMouseDragged, .otherMouseUp:
            return true
        case .scrollWheel:
            return adjust(with: event)
        default:
            return false
        }
    }

    private func click(at point: CGPoint, modifiers: NSEvent.ModifierFlags) {
        guard let session else { return }
        let hit = model.hitTest(dx: Double(point.x - session.center.x),
                                dy: Double(session.center.y - point.y),
                                holding: false,
                                current: interaction.highlighted)
        if case .rootSlot(let rootIndex) = hit {
            clickRootSlot(rootIndex)
            return
        }
        let inHub = hit == .hub
        var slot: Int?
        if case .slot(let index) = hit { slot = index }
        if isEditClick(modifiers), slot != nil || inHub {
            // ⌘-click: open the configurator at this slot (or this level, from the hub).
            let destination = session.editDestination(slot: slot)
            dismiss()
            SettingsRouter.shared.open(destination)
            return
        }
        perform(interaction.click(slot: slot, inHub: inHub))
    }

    /// A click on the dimmed root ring while a folder is fanned out. The open folder's own slot
    /// keeps it open: hovering opened it already, and the click that habitually follows must not
    /// shut it again. Any other root slot closes the folder(s) and is chosen.
    private func clickRootSlot(_ rootIndex: Int) {
        guard model.folderAnchor != rootIndex else { return }
        returnToRoot()
        guard interaction.isOpen else { return }
        perform(interaction.click(slot: rootIndex))
    }

    /// ⌘-click, unless ⌘ is only down because it is part of a trigger still being held.
    private func isEditClick(_ modifiers: NSEvent.ModifierFlags) -> Bool {
        guard modifiers.contains(.command) else { return false }
        let hotKeys = HotKeyCenter.shared
        guard hotKeys.isTriggerHeld, let trigger = hotKeys.registeredTrigger else { return true }
        return !trigger.modifiers.contains(.command)
    }

    /// Scrolling over the ring while a volume or brightness slot is highlighted adjusts it, one
    /// step per notch; the ring stays open. Returns whether the scroll was used.
    private func adjust(with event: NSEvent) -> Bool {
        guard let session, let index = interaction.highlighted, let slot = session.slot(at: index),
              case .media(let command)? = slot.action, Self.adjustment(of: command, up: true) != nil else { return false }
        let steps = scrollStepper.steps(for: event)
        guard steps != 0, let adjusted = Self.adjustment(of: command, up: steps > 0) else { return true }
        let step = Action.media(adjusted)
        let context = ActionContext(frontmostApp: session.frontmostApp, slotTitle: slot.displayTitle, ringCenter: session.center)
        let count = min(abs(steps), 4)
        Task {
            for _ in 0..<count {
                let outcome = await ActionRunner.shared.run(step, context: context)
                switch outcome {
                case .success, .successWithMessage:
                    continue
                case .needsPermission, .failed:
                    ActionFeedback.present(outcome, slot: slot, action: step, anchor: context.ringCenter)
                    return
                }
            }
        }
        return true
    }

    /// The up or down variant of an adjustable media command (volume, brightness), else nil.
    private static func adjustment(of command: MediaCommand, up: Bool) -> MediaCommand? {
        switch command {
        case .volumeUp, .volumeDown: up ? .volumeUp : .volumeDown
        case .brightnessUp, .brightnessDown: up ? .brightnessUp : .brightnessDown
        case .playPause, .nextTrack, .previousTrack, .mute: nil
        }
    }

    /// Clicks outside the ring close it (and still reach whatever is under them).
    private func installMouseMonitors() {
        removeMouseMonitors()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { _ in
            MainActor.assumeIsolated { OverlayController.shared.dismiss() }
        }) {
            mouseMonitors.append(global)
        }
        // Halo's own windows (e.g. the configurator during "Try It") aren't seen by the global monitor.
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            let windowNumber = event.windowNumber
            MainActor.assumeIsolated {
                let controller = OverlayController.shared
                if windowNumber != controller.panel.windowNumber { controller.dismiss() }
            }
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    private func removeMouseMonitors() {
        for monitor in mouseMonitors { NSEvent.removeMonitor(monitor) }
        mouseMonitors.removeAll()
    }

    // MARK: Keys

    private func handle(_ key: HotKeyCenter.NavigationKey) {
        guard session != nil else { return }
        switch key {
        case .escape: perform(interaction.escape())
        case .delete: perform(interaction.back())
        case .return, .space: perform(interaction.confirm())
        case .digit(let number): perform(interaction.number(number))
        case .tab: moveHighlight(to: cycledSlot(clockwise: true))
        case .shiftTab: moveHighlight(to: cycledSlot(clockwise: false))
        case .up: moveHighlight(to: slot(from: interaction.highlighted, toward: .up))
        case .down: moveHighlight(to: slot(from: interaction.highlighted, toward: .down))
        case .left: moveHighlight(to: slot(from: interaction.highlighted, toward: .left))
        case .right: moveHighlight(to: slot(from: interaction.highlighted, toward: .right))
        case .keypad(5): perform(interaction.confirm())
        case .keypad(0): perform(interaction.escape())
        case .keypad(let digit):
            if let direction = Self.direction(ofKeypad: digit) { moveHighlight(to: slot(toward: direction)) }
        }
    }

    private func moveHighlight(to slot: Int) {
        // The pointer takes over again once it moves.
        lastPointer = NSEvent.mouseLocation
        perform(interaction.setHighlight(slot))
    }

    /// Arrow keys: on the ring, or along a fanned-out folder's arc.
    private func slot(from current: Int?, toward direction: RingGeometry.Direction) -> Int {
        if let arc = model.childArc { return ArcNavigation.slot(in: arc, from: current, toward: direction) }
        return model.geometry.slot(from: current, toward: direction)
    }

    /// Keypad directions: the slot (or fanned-out child) nearest the direction.
    private func slot(toward direction: RingGeometry.Direction) -> Int {
        if let arc = model.childArc { return ArcNavigation.slot(in: arc, toward: direction) }
        return model.geometry.slot(toward: direction)
    }

    /// Tab / ⇧Tab: the next slot around the ring (or along the arc) that holds something.
    private func cycledSlot(clockwise: Bool) -> Int {
        let geometry = model.geometry
        var candidate = geometry.slot(after: interaction.highlighted, clockwise: clockwise)
        for _ in 0..<geometry.slotCount {
            if session?.slot(at: candidate)?.isEmpty == false { return candidate }
            candidate = geometry.slot(after: candidate, clockwise: clockwise)
        }
        return geometry.slot(after: interaction.highlighted, clockwise: clockwise)
    }

    /// Keypad digits point like a compass: 8 up, 9 up-right, 6 right … 7 up-left.
    private static func direction(ofKeypad digit: Int) -> RingGeometry.Direction? {
        switch digit {
        case 8: .up
        case 9: .upRight
        case 6: .right
        case 3: .downRight
        case 2: .down
        case 1: .downLeft
        case 4: .left
        case 7: .upLeft
        default: nil
        }
    }

    // MARK: System events

    /// Closes the ring when the world changes under it: Space switch, app switch, display
    /// change, sleep, screen lock, fast user switching.
    private func observeSystemEvents() {
        let workspace = NSWorkspace.shared.notificationCenter
        let closing: [Notification.Name] = [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.willSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ]
        for name in closing {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { OverlayController.shared.dismiss() }
            })
        }
        observers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { OverlayController.shared.applicationActivated(pid: pid) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { OverlayController.shared.dismiss() }
        })
        observers.append(DistributedNotificationCenter.default().addObserver(forName: Self.screenLocked, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { OverlayController.shared.dismiss() }
        })
    }

    private func applicationActivated(pid: pid_t?) {
        guard let session else { return }
        if let pid, pid == session.frontmostApp?.processIdentifier { return }
        guard HotKeyCenter.now - session.openedAt > Timing.activationGrace else { return }
        dismiss()
    }

    // MARK: Watchdog

    /// While the ring is up (or on its way out) a timer checks that navigation keys, polling and
    /// monitors exist only while a session is open, and that the panel is hidden otherwise.
    private func startWatchdog() {
        guard watchdog == nil else { return }
        let timer = Timer(timeInterval: Timing.watchdog, repeats: true) { _ in
            MainActor.assumeIsolated { OverlayController.shared.checkInvariants() }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func checkInvariants() {
        if session != nil {
            if !panel.isVisible {
                Log.overlay.error("Watchdog: ring panel hidden while open; closing")
                dismiss()
            }
            return
        }
        if HotKeyCenter.shared.isNavigating {
            Log.overlay.error("Watchdog: navigation keys outlived the ring; releasing")
            HotKeyCenter.shared.endNavigation()
        }
        if tracker.isRunning { tracker.stop() }
        if !mouseMonitors.isEmpty { removeMouseMonitors() }
        guard hideTask == nil, !isFlashing else { return }   // still dismissing
        if panel.isVisible {
            Log.overlay.error("Watchdog: ring panel left on screen; hiding")
            model.isPresented = false
            panel.orderOut(nil)
        }
        watchdog?.invalidate()
        watchdog = nil
    }
}

/// Arrow-key navigation among a fanned-out folder's children, which sit on an arc around the
/// folder's direction rather than on a full ring.
private enum ArcNavigation {
    /// The child whose direction is closest to `direction`.
    static func slot(in arc: ArcGeometry, toward direction: RingGeometry.Direction) -> Int {
        (0..<arc.count).min { distance(arc, $0, direction) < distance(arc, $1, direction) } ?? 0
    }

    /// With nothing highlighted, the child nearest the arrow's direction. Otherwise one step
    /// along the arc (never past its ends), whichever way turns toward the arrow, so repeated
    /// presses walk along the arc and stop once facing that direction.
    static func slot(in arc: ArcGeometry, from current: Int?, toward direction: RingGeometry.Direction) -> Int {
        guard let current, (0..<arc.count).contains(current) else { return slot(in: arc, toward: direction) }
        return [current, current + 1, current - 1]
            .filter { (0..<arc.count).contains($0) }
            .min { distance(arc, $0, direction) < distance(arc, $1, direction) - 1e-9 } ?? current
    }

    private static func distance(_ arc: ArcGeometry, _ child: Int, _ direction: RingGeometry.Direction) -> Double {
        RingGeometry.angularDistance(arc.angle(of: child), direction.angle)
    }
}

private extension RingInteraction {
    var isHolding: Bool {
        if case .holding = phase { return true }
        return false
    }
}
