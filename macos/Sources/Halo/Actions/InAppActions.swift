import AppKit
@preconcurrency import ApplicationServices
import HaloCore

/// In-app actions: a shortcut or a menu command meant for one specific app (Teams' Mute, Safari's
/// View › Show Sidebar). The app is brought to the front when it isn't already, and with
/// `.bringToFrontAndReturn` the previous app comes back afterwards, so a call can be muted from
/// any app.
enum InAppActions {
    static func run(_ shortcut: AppShortcut, context: ActionContext) async -> ActionOutcome {
        if let missing = PermissionCenter.shared.gate(.accessibility) { return missing }
        let previous = NSWorkspace.shared.frontmostApplication
        let app: NSRunningApplication
        switch await focus(bundleID: shortcut.bundleID, appName: shortcut.appName) {
        case .success(let running): app = running
        case .failure(let failure): return failure.outcome
        }
        let outcome = await KeyActions.run(shortcut.combo)
        await returnIfNeeded(shortcut.delivery, from: app, to: previous, after: outcome)
        return outcome
    }

    static func run(_ item: MenuItemRef, context: ActionContext) async -> ActionOutcome {
        if let missing = PermissionCenter.shared.gate(.accessibility) { return missing }
        guard !item.path.isEmpty else { return .failed("Choose a menu command for this action") }
        let previous = NSWorkspace.shared.frontmostApplication
        let app: NSRunningApplication
        switch await focus(bundleID: item.bundleID, appName: item.appName) {
        case .success(let running): app = running
        case .failure(let failure): return failure.outcome
        }
        let pid = app.processIdentifier
        let path = item.path
        let pressed = await Background.runAX(pid: pid, timeout: 3) { AX.pressMenuPath(pid: pid, path: path) } ?? false
        let outcome: ActionOutcome = pressed
            ? .success
            : .failed("“\(path.joined(separator: " › "))” isn't available in \(item.appName) right now")
        await returnIfNeeded(item.delivery, from: app, to: previous, after: outcome)
        return outcome
    }

    // MARK: Focus

    struct Failure: Error {
        let outcome: ActionOutcome
    }

    /// The running app, brought to the front if another app is in front.
    static func focus(bundleID: String, appName: String) async -> Result<NSRunningApplication, Failure> {
        guard !bundleID.isEmpty else { return .failure(Failure(outcome: .failed("Choose an app for this action"))) }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return .failure(Failure(outcome: .failed("\(appName) isn't running")))
        }
        guard !AppActions.isFrontmost(bundleID: bundleID) else { return .success(app) }
        await AppActions.bringToFront(app, patience: .milliseconds(200))
        guard await AppActions.waitUntilFrontmost(bundleID: bundleID, timeout: .milliseconds(1500)) else {
            return .failure(Failure(outcome: .failed("\(appName) didn't come to the front")))
        }
        return .success(app)
    }

    /// Returns to the app that was in front, if asked to and the action worked.
    static func returnIfNeeded(_ delivery: AppDelivery, from app: NSRunningApplication,
                                       to previous: NSRunningApplication?, after outcome: ActionOutcome) async {
        guard delivery == .bringToFrontAndReturn, let previous, previous.processIdentifier != app.processIdentifier else { return }
        switch outcome {
        case .success, .successWithMessage:
            // Let the app handle the keys before it loses focus.
            try? await Task.sleep(for: .milliseconds(150))
            await AppActions.bringToFront(previous, patience: .milliseconds(250))
        case .needsPermission, .failed:
            break
        }
    }
}

/// A node of an app's menu bar, for the menu-command picker.
nonisolated struct MenuNode: Identifiable, Hashable, Sendable {
    var title: String
    /// The item's own shortcut, e.g. "⇧⌘N", if it has one.
    var shortcut: String?
    var isEnabled: Bool
    var children: [MenuNode]
    /// Titles from the top menu down to this item.
    var path: [String]

    var id: [String] { path }
    var isCommand: Bool { children.isEmpty }
}

/// Reads running apps' menu bars (for the editor) through Accessibility.
enum MenuBarReader {
    /// The app's menus (Apple menu excluded), or nil when the app isn't running or Accessibility
    /// is off. Read off the main actor; large menu bars can take a moment.
    static func menus(ofBundleID bundleID: String) async -> [MenuNode]? {
        guard PermissionCenter.shared.status(.accessibility) == .granted,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return nil }
        let pid = app.processIdentifier
        return await Background.runAX(pid: pid, timeout: 6) { AX.menuTree(pid: pid) } ?? nil
    }
}

nonisolated extension AX {
    /// Presses the menu item at `path` (top menu title first). Titles match ignoring case and a
    /// trailing "…"/"...", so "Save As" matches "Save As…".
    static func pressMenuPath(pid: pid_t, path: [String]) -> Bool {
        guard let bar = element(application(pid), kAXMenuBarAttribute) else { return false }
        var items = children(bar)
        var target: AXUIElement?
        for (depth, title) in path.enumerated() {
            guard let match = items.first(where: { matches(string($0, kAXTitleAttribute), title) }) else { return false }
            if depth == path.count - 1 {
                target = match
            } else {
                // A menu-bar item or submenu item holds one AXMenu whose children are the items.
                items = children(match).flatMap { children($0) }
            }
        }
        guard let target, bool(target, kAXEnabledAttribute) != false else { return false }
        return press(target)
    }

    /// The menu bar as a tree, skipping the Apple menu, separators and items without titles.
    static func menuTree(pid: pid_t) -> [MenuNode]? {
        guard let bar = element(application(pid), kAXMenuBarAttribute) else { return nil }
        return children(bar).dropFirst().compactMap { node($0, parentPath: [], depth: 0) }
    }

    private static func node(_ item: AXUIElement, parentPath: [String], depth: Int) -> MenuNode? {
        guard let title = string(item, kAXTitleAttribute)?.trimmingCharacters(in: .whitespaces), !title.isEmpty else { return nil }
        let path = parentPath + [title]
        // Menus nest rarely deeper than three levels; stop there to keep reads quick.
        let subitems = depth < 3 ? children(item).flatMap { children($0) } : []
        let kids = subitems.compactMap { node($0, parentPath: path, depth: depth + 1) }
        return MenuNode(title: title, shortcut: shortcut(of: item), isEnabled: bool(item, kAXEnabledAttribute) ?? true,
                        children: kids, path: path)
    }

    /// "⇧⌘N" from the item's command character and modifier mask.
    private static func shortcut(of item: AXUIElement) -> String? {
        guard let char = string(item, kAXMenuItemCmdCharAttribute), !char.isEmpty else { return nil }
        let raw = (value(item, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue ?? 0
        // kAXMenuItemModifier*: shift 1, option 2, control 4, no-command 8.
        var text = ""
        if raw & 4 != 0 { text += "⌃" }
        if raw & 2 != 0 { text += "⌥" }
        if raw & 1 != 0 { text += "⇧" }
        if raw & 8 == 0 { text += "⌘" }
        return text + char.uppercased()
    }

    private static func matches(_ candidate: String?, _ title: String) -> Bool {
        guard let candidate else { return false }
        func clean(_ s: String) -> String {
            var t = s.trimmingCharacters(in: .whitespaces)
            for suffix in ["…", "..."] where t.hasSuffix(suffix) { t.removeLast(suffix.count) }
            return t.lowercased()
        }
        return clean(candidate) == clean(title)
    }
}
