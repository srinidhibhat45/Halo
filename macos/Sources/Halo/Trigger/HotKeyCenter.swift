import AppKit
import Carbon.HIToolbox
import HaloCore

/// Global hot keys with press AND release callbacks, built on Carbon's `RegisterEventHotKey`.
///
/// Carbon hot keys need no permission, swallow the keystroke (the frontmost app never sees it),
/// report both key-down and key-up and keep working under Secure Event Input. One C callback,
/// installed on the event dispatcher target, routes every event by hot-key id on the main actor.
///
/// Besides the ring trigger, the center grabs navigation keys (Esc, arrows, digits…) while the
/// ring is open, so they drive the ring without taking keyboard focus from the frontmost app.
@Observable
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    /// Keys the overlay listens to while the ring is open.
    enum NavigationKey: Hashable {
        case escape, `return`, space, tab, shiftTab, delete
        case up, down, left, right
        case digit(Int)   // 0...9
        /// A numeric-keypad digit, 0...9. Keypad Enter arrives as `.return`.
        case keypad(Int)
    }

    /// Why a combo can't, or shouldn't, be the trigger.
    enum TriggerProblem: Equatable {
        /// Can't be used: registering it would swallow ordinary typing.
        case invalid(String)
        /// Usable, but it clashes with a system shortcut or gets in the way of typing.
        case warning(String)

        var message: String {
            switch self {
            case .invalid(let message), .warning(let message): message
            }
        }
    }

    /// While true, the trigger does nothing: its hot key is released so a shortcut recorder can
    /// capture that very combo (Carbon would swallow it otherwise). Resuming registers it again.
    var isSuspended = false {
        didSet {
            guard isSuspended != oldValue else { return }
            isSuspended ? suspendTrigger() : resumeTrigger()
        }
    }

    /// The combo currently registered, if registration succeeded.
    private(set) var registeredTrigger: KeyCombo?

    /// Why the last `setTrigger` failed, in words for the user; nil once a trigger registers.
    private(set) var lastRegistrationError: String?

    /// True while navigation keys are grabbed (between `beginNavigation` and `endNavigation`).
    private(set) var isNavigating = false

    /// True between the trigger's key-down and key-up (auto-repeat presses are latched out).
    @ObservationIgnored private(set) var isTriggerHeld = false

    /// Monotonic seconds since boot: the clock every trigger timestamp uses.
    nonisolated static var now: TimeInterval { GetCurrentEventTime() }

    private nonisolated static let signature: OSType = 0x4841_4C4F   // 'HALO'
    private static let triggerID: UInt32 = 1
    private static let probeID: UInt32 = 2
    private static let firstNavigationID: UInt32 = 100
    /// How long the trigger's modifiers may read as released before a missed key-up is assumed.
    private static let missedReleaseDelay: TimeInterval = 0.15
    /// Auto-repeat presses arrive continuously; a press after this much silence while latched
    /// means a key-up was lost (e.g. a bare function-key trigger, which has no modifiers to poll).
    private static let staleLatch: TimeInterval = 2.5
    /// How long the cached table of system shortcuts is trusted before it is read again.
    private static let systemChordsLifetime: TimeInterval = 60

    @ObservationIgnored private var eventHandler: EventHandlerRef?
    @ObservationIgnored private var triggerRef: EventHotKeyRef?
    @ObservationIgnored private var onTriggerDown: ((TimeInterval) -> Void)?
    @ObservationIgnored private var onTriggerUp: ((TimeInterval) -> Void)?
    @ObservationIgnored private var releaseWatch: Timer?
    @ObservationIgnored private var modifiersReleasedAt: TimeInterval?
    @ObservationIgnored private var lastTriggerPress: TimeInterval = 0
    @ObservationIgnored private var navigationKeys: [UInt32: (ref: EventHotKeyRef, key: NavigationKey)] = [:]
    @ObservationIgnored private var navigationHandler: ((NavigationKey) -> Void)?
    /// Enabled system shortcuts, read at most every `systemChordsLifetime` (see `systemChords()`).
    @ObservationIgnored private var systemChordCache: (chords: Set<Chord>, readAt: TimeInterval)?
    /// Navigation chords last left out because macOS uses them, so each change is logged once.
    @ObservationIgnored private var skippedChords: Set<Chord> = []

    private init() {}

    // MARK: Trigger

    /// Registers (or replaces) the ring trigger. `onDown`/`onUp` receive a monotonic timestamp
    /// in seconds (`HotKeyCenter.now`'s clock). Returns false if the combo is invalid or the
    /// system refused it (e.g. another app owns it); `lastRegistrationError` says why, and no
    /// trigger is registered then. Passing nil unregisters the trigger and returns true.
    @discardableResult
    func setTrigger(_ combo: KeyCombo?, onDown: @escaping (TimeInterval) -> Void, onUp: @escaping (TimeInterval) -> Void) -> Bool {
        onTriggerDown = onDown
        onTriggerUp = onUp
        if let combo, let current = registeredTrigger, Self.sameKeys(combo, current) {
            registeredTrigger = combo   // the label may have changed with the keyboard layout
            lastRegistrationError = nil
            return true
        }
        unregisterTrigger()
        guard let combo else {
            lastRegistrationError = nil
            return true
        }
        if case .invalid(let message)? = Self.problem(for: combo) {
            return failRegistration(message, combo: combo)
        }
        do {
            triggerRef = try register(keyCode: combo.keyCode, modifiers: combo.modifiers, id: Self.triggerID, exclusive: true)
        } catch {
            return failRegistration(Self.describe(error.status, for: combo), combo: combo)
        }
        registeredTrigger = combo
        lastRegistrationError = nil
        Log.trigger.info("Trigger registered: \(Self.displayString(for: combo), privacy: .public)")
        // Navigation keys are also registered with the trigger's modifiers held.
        if isNavigating { registerNavigationKeys() }
        return true
    }

    /// Tries `combo` without keeping it. Returns a user-facing reason it can't be the trigger
    /// (invalid, or already owned by another app), or nil if it would register. The current
    /// trigger always passes.
    func registrationProblem(for combo: KeyCombo) -> String? {
        if let current = registeredTrigger, Self.sameKeys(combo, current) { return nil }
        if case .invalid(let message)? = Self.problem(for: combo) { return message }
        do {
            let ref = try register(keyCode: combo.keyCode, modifiers: combo.modifiers, id: Self.probeID, exclusive: true)
            UnregisterEventHotKey(ref)
            return nil
        } catch {
            return Self.describe(error.status, for: combo)
        }
    }

    private func failRegistration(_ message: String, combo: KeyCombo) -> Bool {
        lastRegistrationError = message
        Log.trigger.error("Trigger \(Self.displayString(for: combo), privacy: .public) not registered: \(message, privacy: .public)")
        return false
    }

    /// Releases the hot key but remembers the combo (`registeredTrigger` stays set).
    private func suspendTrigger() {
        if let triggerRef { UnregisterEventHotKey(triggerRef) }
        triggerRef = nil
        releaseTriggerLatch()
    }

    /// Registers the remembered combo again (unless something already did, e.g. a new trigger
    /// set while suspended).
    private func resumeTrigger() {
        guard triggerRef == nil, let combo = registeredTrigger else { return }
        do {
            triggerRef = try register(keyCode: combo.keyCode, modifiers: combo.modifiers, id: Self.triggerID, exclusive: true)
        } catch {
            registeredTrigger = nil
            _ = failRegistration(Self.describe(error.status, for: combo), combo: combo)
        }
    }

    private func unregisterTrigger() {
        if let triggerRef { UnregisterEventHotKey(triggerRef) }
        triggerRef = nil
        registeredTrigger = nil
        releaseTriggerLatch()
    }

    private func triggerPressed(at time: TimeInterval) {
        guard !isSuspended else { return }
        let silence = time - lastTriggerPress
        lastTriggerPress = time
        // Latch: a second press without a release is key auto-repeat (e.g. a virtual keyboard).
        if isTriggerHeld {
            guard silence > Self.staleLatch else { return }
            // The ring ignores a press while it is held, and the coming key-up settles it.
            Log.trigger.notice("Trigger key-up lost; treating the press as new")
        }
        isTriggerHeld = true
        startReleaseWatch()
        onTriggerDown?(time)
    }

    private func triggerReleased(at time: TimeInterval) {
        guard isTriggerHeld else { return }
        releaseTriggerLatch()
        guard !isSuspended else { return }
        onTriggerUp?(time)
    }

    private func releaseTriggerLatch() {
        isTriggerHeld = false
        releaseWatch?.invalidate()
        releaseWatch = nil
        modifiersReleasedAt = nil
    }

    // MARK: Missed key-up fallback

    /// Carbon doesn't document a release when the modifiers come up before the key, and mouse
    /// software can drop it, so while the trigger is held its modifiers are polled: released for
    /// longer than `missedReleaseDelay` counts as a key-up.
    private func startReleaseWatch() {
        releaseWatch?.invalidate()
        modifiersReleasedAt = nil
        guard let combo = registeredTrigger, !combo.modifiers.subtracting(.function).isEmpty else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { _ in
            MainActor.assumeIsolated { HotKeyCenter.shared.checkTriggerModifiers() }
        }
        RunLoop.main.add(timer, forMode: .common)
        releaseWatch = timer
    }

    private func checkTriggerModifiers() {
        guard isTriggerHeld, let combo = registeredTrigger else {
            releaseTriggerLatch()
            return
        }
        let required = combo.modifiers.subtracting(.function).cgEventFlags
        if CGEventSource.flagsState(.combinedSessionState).contains(required) {
            modifiersReleasedAt = nil
            return
        }
        let now = Self.now
        guard let releasedAt = modifiersReleasedAt else {
            modifiersReleasedAt = now
            return
        }
        guard now - releasedAt > Self.missedReleaseDelay else { return }
        Log.trigger.notice("Trigger key-up missed; releasing from modifier state")
        triggerReleased(at: releasedAt)
    }

    // MARK: Navigation keys

    /// Temporarily grabs navigation keys while the ring is open: Esc, Return, keypad Enter,
    /// Space, Tab, ⇧Tab, Delete, the arrows, the digit row and the keypad digits, each with no
    /// modifiers and again with the trigger's modifiers (so they work while it is still held).
    func beginNavigation(_ handler: @escaping (NavigationKey) -> Void) {
        navigationHandler = handler
        registerNavigationKeys()
    }

    /// Releases the navigation keys.
    func endNavigation() {
        navigationHandler = nil
        unregisterNavigationKeys()
    }

    private struct NavigationBinding {
        var keyCode: Int
        var modifiers: Modifiers = []
        var key: NavigationKey
    }

    private static let navigationBindings: [NavigationBinding] = {
        var bindings: [NavigationBinding] = [
            NavigationBinding(keyCode: kVK_Escape, key: .escape),
            NavigationBinding(keyCode: kVK_Return, key: .return),
            NavigationBinding(keyCode: kVK_ANSI_KeypadEnter, key: .return),
            NavigationBinding(keyCode: kVK_Space, key: .space),
            NavigationBinding(keyCode: kVK_Tab, key: .tab),
            NavigationBinding(keyCode: kVK_Tab, modifiers: .shift, key: .shiftTab),
            NavigationBinding(keyCode: kVK_Delete, key: .delete),
            NavigationBinding(keyCode: kVK_ForwardDelete, key: .delete),
            NavigationBinding(keyCode: kVK_UpArrow, key: .up),
            NavigationBinding(keyCode: kVK_DownArrow, key: .down),
            NavigationBinding(keyCode: kVK_LeftArrow, key: .left),
            NavigationBinding(keyCode: kVK_RightArrow, key: .right),
        ]
        for (index, code) in KeyCode.digitRow.enumerated() {
            bindings.append(NavigationBinding(keyCode: Int(code), key: .digit((index + 1) % 10)))
        }
        let keypad = [kVK_ANSI_Keypad0, kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3, kVK_ANSI_Keypad4,
                      kVK_ANSI_Keypad5, kVK_ANSI_Keypad6, kVK_ANSI_Keypad7, kVK_ANSI_Keypad8, kVK_ANSI_Keypad9]
        for (digit, code) in keypad.enumerated() {
            bindings.append(NavigationBinding(keyCode: code, key: .keypad(digit)))
        }
        return bindings
    }()

    private struct Chord: Hashable {
        var keyCode: UInt32
        var carbonModifiers: UInt32
    }

    private func registerNavigationKeys() {
        unregisterNavigationKeys()
        var modifierSets: [Modifiers] = [[]]
        if let held = registeredTrigger?.modifiers.subtracting(.function), !held.isEmpty {
            modifierSets.append(held)
        }
        // First binding wins a chord (e.g. Tab vs ⇧Tab when the trigger holds ⇧); never the trigger's own.
        var taken = Set<Chord>()
        if let trigger = registeredTrigger {
            taken.insert(Chord(keyCode: UInt32(trigger.keyCode), carbonModifiers: trigger.modifiers.carbonFlags))
        }
        // Never shadow an enabled macOS shortcut: with the default trigger's ⌃⇧⌘ held, 3 and 4
        // are the screenshot-to-clipboard shortcuts.
        let reserved = systemChords()
        var skipped: [Chord: String] = [:]
        var nextID = Self.firstNavigationID
        for held in modifierSets {
            for binding in Self.navigationBindings {
                let modifiers = held.union(binding.modifiers)
                let chord = Chord(keyCode: UInt32(binding.keyCode), carbonModifiers: modifiers.carbonFlags)
                guard taken.insert(chord).inserted else { continue }
                if reserved.contains(chord) {
                    skipped[chord] = modifiers.symbols + KeyboardLayout.label(forKeyCode: UInt16(binding.keyCode))
                    continue
                }
                do {
                    let ref = try register(keyCode: UInt16(binding.keyCode), modifiers: modifiers, id: nextID, exclusive: false)
                    navigationKeys[nextID] = (ref, binding.key)
                    nextID += 1
                } catch {
                    Log.trigger.error("Navigation key \(binding.keyCode) (\(modifiers.symbols, privacy: .public)) not registered: \(error.status)")
                }
            }
        }
        if Set(skipped.keys) != skippedChords {
            skippedChords = Set(skipped.keys)
            if !skipped.isEmpty {
                let names = skipped.values.sorted().joined(separator: ", ")
                Log.trigger.info("Navigation keys left to macOS, which uses them: \(names, privacy: .public)")
            }
        }
        isNavigating = true
    }

    /// Enabled system shortcuts as chords, re-read when the cache is older than
    /// `systemChordsLifetime` (the user may change them in Keyboard Settings meanwhile).
    private func systemChords() -> Set<Chord> {
        let now = Self.now
        if let cache = systemChordCache, now - cache.readAt < Self.systemChordsLifetime { return cache.chords }
        let chords = Self.readSystemChords()
        systemChordCache = (chords, now)
        return chords
    }

    private func unregisterNavigationKeys() {
        for entry in navigationKeys.values { UnregisterEventHotKey(entry.ref) }
        navigationKeys.removeAll()
        isNavigating = false
    }

    // MARK: Carbon plumbing

    private struct RegistrationError: Error {
        var status: OSStatus
    }

    private func register(keyCode: UInt16, modifiers: Modifiers, id: UInt32, exclusive: Bool) throws(RegistrationError) -> EventHotKeyRef {
        let installed = installEventHandlerIfNeeded()
        guard installed == noErr else { throw RegistrationError(status: installed) }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), modifiers.carbonFlags,
                                         EventHotKeyID(signature: Self.signature, id: id),
                                         GetEventDispatcherTarget(),
                                         OptionBits(exclusive ? kEventHotKeyExclusive : kEventHotKeyNoOptions),
                                         &ref)
        guard status == noErr, let ref else { throw RegistrationError(status: status == noErr ? OSStatus(eventInternalErr) : status) }
        return ref
    }

    private func installEventHandlerIfNeeded() -> OSStatus {
        guard eventHandler == nil else { return noErr }
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        // A C callback can't capture context; it routes through the singleton. Carbon delivers on the main thread.
        let callback: EventHandlerUPP = { _, event, _ in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr, hotKeyID.signature == HotKeyCenter.signature else { return OSStatus(eventNotHandledErr) }
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            let time = GetEventTime(event)
            MainActor.assumeIsolated {
                HotKeyCenter.shared.dispatch(id: hotKeyID.id, pressed: pressed, time: time)
            }
            return noErr
        }
        let status = InstallEventHandler(GetEventDispatcherTarget(), callback, specs.count, &specs, nil, &eventHandler)
        if status != noErr { Log.trigger.fault("Could not install the hot key handler: \(status)") }
        return status
    }

    private func dispatch(id: UInt32, pressed: Bool, time: TimeInterval) {
        if id == Self.triggerID {
            if pressed { triggerPressed(at: time) } else { triggerReleased(at: time) }
            return
        }
        guard pressed, let key = navigationKeys[id]?.key else { return }
        navigationHandler?(key)
    }

    private static func sameKeys(_ a: KeyCombo, _ b: KeyCombo) -> Bool {
        a.keyCode == b.keyCode && a.modifiers.subtracting(.function) == b.modifiers.subtracting(.function)
    }

    private static func describe(_ status: OSStatus, for combo: KeyCombo) -> String {
        let shown = displayString(for: combo)
        return switch Int(status) {
        case eventHotKeyExistsErr:
            "Another app already uses \(shown). Choose a different shortcut, or remove it from that app."
        case eventInternalErr:
            "macOS doesn't allow \(shown) as a global shortcut. Try adding ⌘ or ⌃."
        default:
            "macOS couldn't register \(shown) (error \(status))."
        }
    }

    /// `combo` as the current keyboard layout labels its key. Hot keys go by key position, and the
    /// stored label may come from another layout: the default trigger ⌃⇧⌘H is pressed as ⌃⇧⌘D on
    /// Dvorak.
    static func displayString(for combo: KeyCombo) -> String {
        combo.modifiers.symbols + KeyboardLayout.label(forKeyCode: combo.keyCode)
    }

    // MARK: Validation

    /// True if `combo` can be used as a trigger (has a modifier or is a function key, and is
    /// not reserved by the system). Returns a user-facing problem, or nil if the combo is fine;
    /// `problem(for:)` tells blocking problems from warnings.
    static func validate(_ combo: KeyCombo) -> String? { problem(for: combo)?.message }

    /// Checks `combo` against the trigger rules: it needs ⌘, ⌃ or ⌥ (⇧ alone isn't enough)
    /// unless it is a function key F1–F20. Warns on ⌥-only and ⌥⇧-only combos, standard macOS
    /// shortcuts and enabled system shortcuts (System Settings › Keyboard).
    static func problem(for combo: KeyCombo) -> TriggerProblem? {
        let modifiers = combo.modifiers.subtracting(.function)
        let isFunctionKey = functionKeyCodes.contains(combo.keyCode)
        let shown = displayString(for: combo)
        if modifiers.isDisjoint(with: [.command, .control, .option]), !isFunctionKey {
            return .invalid(modifiers.isEmpty
                ? "Add ⌘, ⌃ or ⌥. Without one, \(KeyboardLayout.label(forKeyCode: combo.keyCode)) would stop typing everywhere. Function keys F1–F20 work on their own."
                : "⇧ alone isn't enough. Add ⌘, ⌃ or ⌥, or use a function key F1–F20.")
        }
        if let reserved = reservedShortcuts.first(where: { $0.keyCode == combo.keyCode && $0.modifiers == modifiers }) {
            return .warning("\(shown) is the standard shortcut for \(reserved.name). Using it for Halo stops it working everywhere else.")
        }
        if modifiers == [.option] || modifiers == [.option, .shift] {
            return .warning("Shortcuts with only ⌥ or ⌥⇧ block typing special characters such as é and ©. Consider adding ⌘ or ⌃.")
        }
        if readSystemChords().contains(Chord(keyCode: UInt32(combo.keyCode), carbonModifiers: combo.modifiers.carbonFlags)) {
            return .warning("macOS already uses \(shown) (System Settings › Keyboard › Keyboard Shortcuts). Turn it off there or choose another shortcut.")
        }
        return nil
    }

    private static let functionKeyCodes: Set<UInt16> = [
        KeyCode.f1, KeyCode.f2, KeyCode.f3, KeyCode.f4, KeyCode.f5, KeyCode.f6, KeyCode.f7, KeyCode.f8, KeyCode.f9, KeyCode.f10,
        KeyCode.f11, KeyCode.f12, KeyCode.f13, KeyCode.f14, KeyCode.f15, KeyCode.f16, KeyCode.f17, KeyCode.f18, KeyCode.f19, KeyCode.f20,
    ]

    private struct ReservedShortcut {
        var keyCode: UInt16
        var modifiers: Modifiers
        var name: String
    }

    private static let reservedShortcuts: [ReservedShortcut] = [
        ReservedShortcut(keyCode: KeyCode.tab, modifiers: .command, name: "switching apps"),
        ReservedShortcut(keyCode: KeyCode.space, modifiers: .command, name: "Spotlight"),
        ReservedShortcut(keyCode: KeyCode.q, modifiers: .command, name: "Quit"),
        ReservedShortcut(keyCode: KeyCode.w, modifiers: .command, name: "Close"),
        ReservedShortcut(keyCode: KeyCode.h, modifiers: .command, name: "Hide"),
        ReservedShortcut(keyCode: KeyCode.m, modifiers: .command, name: "Minimize"),
        ReservedShortcut(keyCode: KeyCode.c, modifiers: .command, name: "Copy"),
        ReservedShortcut(keyCode: KeyCode.v, modifiers: .command, name: "Paste"),
        ReservedShortcut(keyCode: KeyCode.x, modifiers: .command, name: "Cut"),
        ReservedShortcut(keyCode: KeyCode.z, modifiers: .command, name: "Undo"),
        ReservedShortcut(keyCode: KeyCode.three, modifiers: [.shift, .command], name: "screenshots"),
        ReservedShortcut(keyCode: KeyCode.four, modifiers: [.shift, .command], name: "screenshots"),
        ReservedShortcut(keyCode: KeyCode.five, modifiers: [.shift, .command], name: "the screenshot toolbar"),
        ReservedShortcut(keyCode: KeyCode.escape, modifiers: [.option, .command], name: "Force Quit"),
        ReservedShortcut(keyCode: KeyCode.q, modifiers: [.control, .command], name: "Lock Screen"),
        ReservedShortcut(keyCode: KeyCode.return, modifiers: .control, name: "showing the context menu"),
    ]

    /// Enabled system shortcuts (Mission Control, input sources, screenshots…) as chords.
    /// `CopySymbolicHotKeys` copies the whole table: fine for validation or once per ring, never
    /// per event.
    private static func readSystemChords() -> Set<Chord> {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr,
              let entries = unmanaged?.takeRetainedValue() as? [[String: Any]] else { return [] }
        let relevant = UInt32(cmdKey | shiftKey | optionKey | controlKey)
        return Set(entries.compactMap { entry -> Chord? in
            guard (entry[kHISymbolicHotKeyEnabled as String] as? Bool) == true,
                  let code = (entry[kHISymbolicHotKeyCode as String] as? Int).flatMap({ UInt32(exactly: $0) }),
                  let modifiers = entry[kHISymbolicHotKeyModifiers as String] as? Int else { return nil }
            return Chord(keyCode: code, carbonModifiers: UInt32(truncatingIfNeeded: modifiers) & relevant)
        })
    }
}
