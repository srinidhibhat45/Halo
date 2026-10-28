import AppKit
@preconcurrency import ApplicationServices

/// Thin wrappers over the Accessibility C API. Every call is a blocking IPC round trip to the
/// target app, so call these through `Background.runAX(pid:timeout:_:)`: off the main actor for
/// other apps, on it for Halo's own windows (AppKit answers those in-process).
nonisolated enum AX {
    /// Per-element IPC timeout in seconds (the system default is several seconds).
    static let messagingTimeout: Float = 0.5

    static func application(_ pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }

    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let child = unsafeDowncast(value, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(child, messagingTimeout)
        return child
    }

    static func children(_ element: AXUIElement, _ attribute: String = kAXChildrenAttribute) -> [AXUIElement] {
        let elements = (value(element, attribute) as? [AXUIElement]) ?? []
        for child in elements { AXUIElementSetMessagingTimeout(child, messagingTimeout) }
        return elements
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        value(element, attribute) as? Bool
    }

    static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgPoint, &point) ? point : nil
    }

    static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgSize, &size) ? size : nil
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
    }

    @discardableResult
    static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    // MARK: Menus

    /// Presses an item in an app's status-item ("extras") menu bar: the one whose AXIdentifier is
    /// `identifier`, or the first item when `identifier` is nil.
    static func pressMenuExtra(pid: pid_t, identifier: String?) -> Bool {
        guard let bar = element(application(pid), kAXExtrasMenuBarAttribute) else { return false }
        let items = children(bar)
        let match: AXUIElement? = if let identifier {
            items.first { string($0, kAXIdentifierAttribute) == identifier }
        } else {
            items.first
        }
        guard let match else { return false }
        return press(match)
    }

    /// Presses the first enabled menu item (top-level menus only) whose title is one of `titles`.
    static func pressMenuItem(pid: pid_t, titles: Set<String>) -> Bool {
        guard let bar = element(application(pid), kAXMenuBarAttribute) else { return false }
        // Skip the Apple menu; the app's own menus follow it.
        for barItem in children(bar).dropFirst() {
            for menu in children(barItem) {
                for item in children(menu) {
                    guard let title = string(item, kAXTitleAttribute), titles.contains(title) else { continue }
                    if bool(item, kAXEnabledAttribute) == false { continue }
                    return press(item)
                }
            }
        }
        return false
    }
}
