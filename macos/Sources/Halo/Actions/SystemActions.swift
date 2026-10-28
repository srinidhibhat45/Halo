import AppKit
import HaloCore
import IOKit.pwr_mgt

/// System commands. Globe (Fn) shortcuts can't be synthesized, so each command takes the most
/// reliable route available on macOS 26+: Apple's own launcher apps, system shortcuts as the user
/// bound them, Control Center's menu bar items, or power management calls.
enum SystemActions {
    private static let missionControlLauncher = "/System/Applications/Mission Control.app/Contents/MacOS/Mission Control"
    private static let controlCenterID = "com.apple.controlcenter"
    /// System Events answers in well under a second once Automation is decided.
    private static let darkModeTimeout: TimeInterval = 5

    static func run(_ command: SystemCommand) async -> ActionOutcome {
        switch command {
        case .missionControl: return await missionControl(argument: nil)
        case .showDesktop: return await missionControl(argument: "1")
        case .appExpose: return await missionControl(argument: "2")
        case .launchpad:
            // macOS 26 replaced Launchpad with Apps; its launcher toggles the Apps view.
            return await AppActions.launch(path: "/System/Applications/Apps.app", newInstance: true, activates: false)
                ? .success : .failed("Apps isn't available")
        case .siri:
            return await AppActions.launch(path: "/System/Applications/Siri.app", newInstance: true)
                ? .success : .failed("Siri isn't available")
        case .screenSaver:
            return await AppActions.launch(path: "/System/Library/CoreServices/ScreenSaverEngine.app")
                ? .success : .failed("Couldn't start the screen saver")
        case .systemSettings:
            return await AppActions.launch(path: "/System/Applications/System Settings.app")
                ? .success : .failed("Couldn't open System Settings")
        case .notificationCenter: return await notificationCenter()
        case .spotlight: return await spotlight()
        case .lockScreen: return await lockScreen()
        case .sleepDisplay: return await pmset("displaysleepnow", failure: "Couldn't turn off the display")
        case .sleep: return await sleep()
        case .emojiPicker:
            return await shortcut(CGKeyCode(KeyCode.space), [.maskControl, .maskCommand])   // Edit › Emoji & Symbols
        case .dictation: return await dictation()
        case .toggleDarkMode: return await toggleDarkMode()
        case .doNotDisturb: return await doNotDisturb()
        case .forceQuit: return await shortcut(CGKeyCode(KeyCode.escape), [.maskAlternate, .maskCommand])
        }
    }

    // MARK: Routes

    /// Apple's Mission Control launcher: no argument = Mission Control, "1" = Show Desktop,
    /// "2" = App Exposé for the frontmost app (verified by disassembly on 27.2). Run directly so it
    /// never activates and steals "frontmost" from the app App Exposé should show.
    private static func missionControl(argument: String?) async -> ActionOutcome {
        // It posts its Dock notification and exits at once; a launch is all that matters.
        let result = await ProcessRunner.run(missionControlLauncher, argument.map { [$0] } ?? [], timeout: 2)
        return result.launchError == nil ? .success : .failed("Mission Control isn't available")
    }

    private static func shortcut(_ keyCode: CGKeyCode, _ modifiers: CGEventFlags) async -> ActionOutcome {
        if let missing = PermissionCenter.shared.gate(.accessibility) { return missing }
        await KeySender.waitForTriggerRelease()
        return await KeySender.press(keyCode, modifiers: modifiers) ? .success : .failed("Couldn't send the shortcut")
    }

    /// The user's "Show Notification Center" shortcut if they set one, else Control Center's clock.
    private static func notificationCenter() async -> ActionOutcome {
        if let missing = PermissionCenter.shared.gate(.accessibility) { return missing }
        if let binding = SymbolicHotKey.notificationCenter.binding {
            await KeySender.waitForTriggerRelease()
            if await KeySender.press(binding) { return .success }
        }
        return await pressMenuExtra(controlCenterID, identifier: "com.apple.menuextra.clock")
            ? .success : .failed("Couldn't open Notification Center")
    }

    /// Spotlight's shortcut as bound (⌘Space by default), else its menu bar item.
    private static func spotlight() async -> ActionOutcome {
        if let missing = PermissionCenter.shared.gate(.accessibility) { return missing }
        if let binding = SymbolicHotKey.spotlight.binding {
            await KeySender.waitForTriggerRelease()
            if await KeySender.press(binding) { return .success }
        }
        return await pressMenuExtra("com.apple.Spotlight", identifier: nil)
            ? .success : .failed("Turn on Spotlight's shortcut in Keyboard Settings")
    }

    /// ⌃⌘Q (Apple menu › Lock Screen); without Accessibility, the private immediate-lock call.
    private static func lockScreen() async -> ActionOutcome {
        if PermissionCenter.shared.isGranted(.accessibility) {
            await KeySender.waitForTriggerRelease()
            if await KeySender.press(character: "q", modifiers: [.maskControl, .maskCommand], fallback: CGKeyCode(KeyCode.q)) {
                return .success
            }
        }
        return PrivateLock.lockNow() ? .success : .needsPermission(.accessibility)
    }

    private static func sleep() async -> ActionOutcome {
        // IOPMSleepSystem is allowed for the console user; pmset is the fallback.
        let port = IOPMFindPowerManagement(mach_port_t(MACH_PORT_NULL))
        if port != 0 {
            defer { IOServiceClose(port) }
            if IOPMSleepSystem(port) == kIOReturnSuccess { return .success }
        }
        return await pmset("sleepnow", failure: "Couldn't put the Mac to sleep")
    }

    /// Display sleep has no public API on Apple silicon (no IODisplayWrangler); pmset does it.
    private static func pmset(_ argument: String, failure: String) async -> ActionOutcome {
        let result = await ProcessRunner.run("/usr/bin/pmset", [argument], timeout: 5)
        return result.succeeded ? .success : .failed(failure)
    }

    /// Fn-D can't be synthesized; the frontmost app's Edit › Start Dictation item does the same.
    private static func dictation() async -> ActionOutcome {
        if let missing = PermissionCenter.shared.gate(.accessibility) { return missing }
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return .failed("No app is in front") }
        let titles = dictationMenuTitles()
        let pressed = await Background.runAX(pid: pid, timeout: 3) { AX.pressMenuItem(pid: pid, titles: titles) }
        return pressed == true ? .success : .failed("Dictation isn't available in this app")
    }

    /// AppKit's own titles for the item, in the user's language, plus the English ones.
    private static func dictationMenuTitles() -> Set<String> {
        var titles: Set<String> = ["Start Dictation…", "Start Dictation", "Stop Dictation"]
        if let appKit = Bundle(identifier: "com.apple.AppKit") {
            for key in titles {
                titles.insert(appKit.localizedString(forKey: key, value: key, table: "DictationManager"))
            }
        }
        return titles
    }

    /// System Events' appearance preference (Automation for System Events). The consent question,
    /// if still open, is asked first; the script then runs in osascript, so the Apple Event never
    /// blocks the main thread (NSAppleScript would, for as long as System Events takes).
    private static func toggleDarkMode() async -> ActionOutcome {
        let permission = await PermissionCenter.shared.checkAutomation(prompting: true)
        guard permission == .granted else { return .needsPermission(.automation) }
        let source = """
        tell application "System Events" to tell appearance preferences
            set dark mode to not dark mode
            return dark mode
        end tell
        """
        let result = await ProcessRunner.run("/usr/bin/osascript", ["-e", source], timeout: darkModeTimeout)
        if result.succeeded {
            switch result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) {
            case "true": return .successWithMessage("Dark Mode on")
            case "false": return .successWithMessage("Dark Mode off")
            default: return .success
            }
        }
        if result.stderr.contains("(-1743)") { return .needsPermission(.automation) }   // errAEEventNotPermitted
        let reason = result.launchError ?? (result.timedOut ? "timed out" : ProcessResult.firstLine(of: result.stderr) ?? "exit \(result.status)")
        Log.actions.error("Dark Mode script failed: \(reason, privacy: .public)")
        return .failed("Couldn't switch Dark Mode")
    }

    /// There is no public Focus API. With a "Do Not Disturb" shortcut assigned in Keyboard Settings
    /// it toggles in one go; otherwise Control Center's Focus menu (or Control Center) opens.
    private static func doNotDisturb() async -> ActionOutcome {
        if let missing = PermissionCenter.shared.gate(.accessibility) { return missing }
        if let binding = SymbolicHotKey.doNotDisturb.binding {
            await KeySender.waitForTriggerRelease()
            if await KeySender.press(binding) { return .successWithMessage("Do Not Disturb toggled") }
        }
        if await pressMenuExtra(controlCenterID, identifier: "com.apple.menuextra.focusmode") { return .success }
        if await pressMenuExtra(controlCenterID, identifier: "com.apple.menuextra.controlcenter") {
            return .successWithMessage("Choose Focus in Control Center")
        }
        return .failed("Assign a Do Not Disturb shortcut in Keyboard Settings")
    }

    private static func pressMenuExtra(_ bundleID: String, identifier: String?) async -> Bool {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier else {
            return false
        }
        return await Background.runAX(pid: pid, timeout: 2) { AX.pressMenuExtra(pid: pid, identifier: identifier) } == true
    }
}

/// `SACLockScreenImmediate` from the private login framework: locks without a keystroke or any
/// permission. Only used when Accessibility is missing.
private enum PrivateLock {
    private typealias LockFunction = @convention(c) () -> Int32

    static func lockNow() -> Bool {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
              let symbol = dlsym(handle, "SACLockScreenImmediate") else { return false }
        return unsafeBitCast(symbol, to: LockFunction.self)() == 0
    }
}
