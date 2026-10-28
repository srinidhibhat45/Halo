import AppKit
@preconcurrency import ApplicationServices
import HaloCore

/// Clicks an app's own controls by their accessible names, in order: for things an app offers
/// only as buttons (Teams: More actions › Record › Confirm). Each step waits for its control to
/// appear, since menus and dialogs open a moment after the click before.
enum ButtonActions {
    static func run(_ sequence: ButtonSequence, context: ActionContext) async -> ActionOutcome {
        if let missing = PermissionCenter.shared.gate(.accessibility) { return missing }
        guard sequence.steps.contains(where: { !$0.names.isEmpty }) else { return .failed("Add the buttons this action clicks") }
        let previous = NSWorkspace.shared.frontmostApplication
        let app: NSRunningApplication
        switch await InAppActions.focus(bundleID: sequence.bundleID, appName: sequence.appName) {
        case .success(let running): app = running
        case .failure(let failure): return failure.outcome
        }
        let pid = app.processIdentifier
        for step in sequence.steps where !step.names.isEmpty {
            let wait: Duration = step.isOptional ? .milliseconds(900) : .milliseconds(2500)
            if await click(step.names, pid: pid, within: wait) {
                // Let the menu or dialog this click opens appear.
                try? await Task.sleep(for: .milliseconds(150))
            } else if !step.isOptional {
                return .failed("Couldn't find “\(step.names[0])” in \(sequence.appName). Is the right window open?")
            }
        }
        let outcome = ActionOutcome.success
        await InAppActions.returnIfNeeded(sequence.delivery, from: app, to: previous, after: outcome)
        return outcome
    }

    /// Looks for a control named one of `names` until `within` has passed, and clicks it.
    private static func click(_ names: [String], pid: pid_t, within: Duration) async -> Bool {
        let deadline = ContinuousClock.now + within
        repeat {
            if await Background.runAX(pid: pid, timeout: 3, { AX.pressControl(pid: pid, names: names) }) == true { return true }
            try? await Task.sleep(for: .milliseconds(150))
        } while ContinuousClock.now < deadline
        return false
    }

    /// The control under the pointer, for the editor's "point at it" step: its app and name.
    static func controlUnderPointer() async -> (bundleID: String, appName: String, name: String)? {
        guard PermissionCenter.shared.status(.accessibility) == .granted else { return nil }
        // AX uses top-left origin coordinates on the primary display.
        let mouse = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let point = CGPoint(x: mouse.x, y: primaryHeight - mouse.y)
        guard let found = await Background.run(timeout: 2, { AX.namedControl(at: point) }), let found else { return nil }
        guard let app = NSRunningApplication(processIdentifier: found.pid), let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier else { return nil }
        return (bundleID, app.localizedName ?? bundleID, found.name)
    }
}

nonisolated extension AX {
    /// Roles that respond to a click.
    private static let pressableRoles: Set<String> = [
        kAXButtonRole, kAXMenuItemRole, kAXMenuButtonRole, kAXPopUpButtonRole, kAXCheckBoxRole,
        kAXRadioButtonRole, kAXMenuBarItemRole, kAXDisclosureTriangleRole, "AXLink", "AXTab",
    ]
    /// Bounds a search so a huge web page can't stall the action.
    private static let searchLimit = 6000

    /// Presses the first control (in `names` order of preference) found in the app's windows,
    /// focused window first. Names match title, description or a text label, ignoring case and a
    /// trailing "…"; a matching label clicks its nearest clickable ancestor.
    static func pressControl(pid: pid_t, names: [String]) -> Bool {
        let wanted = names.map(normalizedName)
        let app = application(pid)
        var roots: [AXUIElement] = []
        if let focused = element(app, kAXFocusedWindowAttribute) { roots.append(focused) }
        for window in children(app, kAXWindowsAttribute) where !roots.contains(where: { CFEqual($0, window) }) {
            roots.append(window)
        }
        var best: (rank: Int, element: AXUIElement)?
        var queue = roots
        var head = 0
        while head < queue.count, head < searchLimit {
            let node = queue[head]
            head += 1
            let info = attributes(of: node)
            if let rank = info.names.compactMap({ wanted.firstIndex(of: normalizedName($0)) }).min(),
               best.map({ rank < $0.rank }) ?? true,
               let target = info.isPressable ? node : pressableAncestor(of: node) {
                best = (rank, target)
                if rank == 0 { break }
            }
            queue.append(contentsOf: info.children)
        }
        guard let target = best?.element else { return false }
        return press(target) || AXUIElementPerformAction(target, kAXShowMenuAction as CFString) == .success
    }

    /// The named control at a screen point (top-left coordinates), with its process.
    static func namedControl(at point: CGPoint) -> (pid: pid_t, name: String)? {
        let systemWide = AXUIElementCreateSystemWide()
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit) == .success, var current = hit else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(current, &pid)
        // The element under the pointer may be an icon inside the button: walk up to a name.
        for _ in 0..<4 {
            if let name = attributes(of: current).names.first(where: { !$0.isEmpty }) { return (pid, name) }
            guard let parent = element(current, kAXParentAttribute) else { break }
            current = parent
        }
        return nil
    }

    private struct NodeInfo {
        var names: [String]
        var isPressable: Bool
        var children: [AXUIElement]
    }

    /// Role, names and children in one round trip.
    private static func attributes(of node: AXUIElement) -> NodeInfo {
        let keys = [kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXEnabledAttribute, kAXChildrenAttribute] as CFArray
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(node, keys, AXCopyMultipleAttributeOptions(rawValue: 0), &values) == .success,
              let array = values as? [AnyObject], array.count == 6 else {
            return NodeInfo(names: [], isPressable: false, children: [])
        }
        let role = array[0] as? String ?? ""
        let enabled = (array[4] as? NSNumber)?.boolValue ?? true
        var names = [array[1] as? String, array[2] as? String].compactMap { $0 }.filter { !$0.isEmpty }
        // Text labels carry their text in the value.
        if role == kAXStaticTextRole, let value = array[3] as? String, !value.isEmpty { names.append(value) }
        let kids = (array[5] as? [AXUIElement]) ?? []
        return NodeInfo(names: names, isPressable: enabled && pressableRoles.contains(role), children: kids)
    }

    private static func pressableAncestor(of node: AXUIElement) -> AXUIElement? {
        var current = node
        for _ in 0..<3 {
            guard let parent = element(current, kAXParentAttribute) else { return nil }
            if attributes(of: parent).isPressable { return parent }
            current = parent
        }
        return nil
    }

    private static func normalizedName(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in ["…", "..."] where t.hasSuffix(suffix) { t.removeLast(suffix.count) }
        return t.lowercased()
    }
}
