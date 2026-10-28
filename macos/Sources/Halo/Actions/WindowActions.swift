import AppKit
@preconcurrency import ApplicationServices
import HaloCore

/// Window commands for the frontmost app's focused window, through the Accessibility API.
///
/// Built-in tiling (Globe-⌃ shortcuts) can't be synthesized, so layouts are computed here and
/// applied the way Rectangle does: size → position → size, with AXEnhancedUserInterface off.
enum WindowActions {
    static func run(_ command: WindowCommand, context: ActionContext) async -> ActionOutcome {
        if let missing = PermissionCenter.shared.gate(.accessibility) { return missing }
        guard let app = NSWorkspace.shared.frontmostApplication ?? context.frontmostApp else {
            return .failed("No app is in front")
        }
        let pid = app.processIdentifier
        let screens = WindowMover.Screen.current()
        let result = await Background.runAX(pid: pid, timeout: 3) { WindowMover.perform(command, pid: pid, screens: screens) }
        switch result {
        case .done?: return .success
        case .noWindow?: return .failed("\(app.localizedName ?? "This app") has no window to arrange")
        case .fullScreen?: return .failed("Exit full screen first")
        case .singleDisplay?: return .failed("Only one display is connected")
        case .refused(let reason)?: return .failed(reason)
        case nil: return .failed("\(app.localizedName ?? "The app") didn't respond")
        }
    }
}

/// The blocking AX work behind `WindowActions`. Coordinates are AX's: origin at the top-left of
/// the primary display, y down.
nonisolated enum WindowMover {
    enum Result: Sendable {
        case done, noWindow, fullScreen, singleDisplay
        case refused(String)
    }

    struct Screen: Sendable, Equatable {
        var frame: CGRect
        /// Excludes the menu bar and Dock.
        var visibleFrame: CGRect

        /// All screens, converted from AppKit's bottom-left coordinates.
        @MainActor
        static func current() -> [Screen] {
            let screens = NSScreen.screens
            guard let primaryHeight = screens.first?.frame.height else { return [] }
            func flip(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height) }
            return screens.map { Screen(frame: flip($0.frame), visibleFrame: flip($0.visibleFrame)) }
        }
    }

    private static let fullScreenAttribute = "AXFullScreen"
    private static let enhancedUIAttribute = "AXEnhancedUserInterface"

    static func perform(_ command: WindowCommand, pid: pid_t, screens: [Screen]) -> Result {
        let app = AX.application(pid)
        guard let window = AX.element(app, kAXFocusedWindowAttribute)
                ?? AX.element(app, kAXMainWindowAttribute)
                ?? AX.children(app, kAXWindowsAttribute).first else { return .noWindow }
        let isFullScreen = AX.bool(window, fullScreenAttribute) == true

        switch command {
        case .toggleFullScreen:
            if AX.set(window, fullScreenAttribute, NSNumber(value: !isFullScreen)) { return .done }
            if let button = AX.element(window, kAXFullScreenButtonAttribute), AX.press(button) { return .done }
            return .refused("This window can't go full screen")
        case .close:
            if let button = AX.element(window, kAXCloseButtonAttribute), AX.press(button) { return .done }
            return .refused("This window can't be closed")
        case .minimize:
            if isFullScreen { return .fullScreen }
            if AX.set(window, kAXMinimizedAttribute, NSNumber(value: true)) { return .done }
            if let button = AX.element(window, kAXMinimizeButtonAttribute), AX.press(button) { return .done }
            return .refused("This window can't be minimized")
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf, .maximize, .center, .nextDisplay:
            if isFullScreen { return .fullScreen }
            guard let origin = AX.point(window, kAXPositionAttribute),
                  let size = AX.size(window, kAXSizeAttribute) else { return .refused("This window can't be moved") }
            if command == .nextDisplay, screens.count < 2 { return .singleDisplay }
            guard let target = targetFrame(command, window: CGRect(origin: origin, size: size), screens: screens) else {
                return .noWindow
            }
            return setFrame(target, of: window, app: app) ? .done : .refused("This window can't be moved")
        }
    }

    /// Where `command` puts a window currently at `window` (pure geometry).
    static func targetFrame(_ command: WindowCommand, window: CGRect, screens: [Screen]) -> CGRect? {
        guard let index = screenIndex(for: window, in: screens) else { return nil }
        let area = screens[index].visibleFrame
        let halfWidth = (area.width / 2).rounded(.down)
        let halfHeight = (area.height / 2).rounded(.down)
        switch command {
        case .leftHalf:
            return CGRect(x: area.minX, y: area.minY, width: halfWidth, height: area.height)
        case .rightHalf:
            return CGRect(x: area.minX + halfWidth, y: area.minY, width: area.width - halfWidth, height: area.height)
        case .topHalf:
            return CGRect(x: area.minX, y: area.minY, width: area.width, height: halfHeight)
        case .bottomHalf:
            return CGRect(x: area.minX, y: area.minY + halfHeight, width: area.width, height: area.height - halfHeight)
        case .maximize:
            return area
        case .center:
            let size = CGSize(width: min(window.width, area.width), height: min(window.height, area.height))
            return CGRect(x: (area.midX - size.width / 2).rounded(), y: (area.midY - size.height / 2).rounded(),
                          width: size.width, height: size.height)
        case .nextDisplay:
            let next = screens[(index + 1) % screens.count].visibleFrame
            // Keep the window's position and size relative to the visible area.
            let scaleX = next.width / max(area.width, 1)
            let scaleY = next.height / max(area.height, 1)
            let size = CGSize(width: min(window.width * scaleX, next.width), height: min(window.height * scaleY, next.height))
            let x = next.minX + (window.minX - area.minX) * scaleX
            let y = next.minY + (window.minY - area.minY) * scaleY
            return CGRect(x: min(max(x, next.minX), next.maxX - size.width).rounded(),
                          y: min(max(y, next.minY), next.maxY - size.height).rounded(),
                          width: size.width.rounded(), height: size.height.rounded())
        case .minimize, .toggleFullScreen, .close:
            return nil
        }
    }

    /// The screen showing most of `window` (else the one under its centre, else the first).
    static func screenIndex(for window: CGRect, in screens: [Screen]) -> Int? {
        guard !screens.isEmpty else { return nil }
        let overlaps = screens.map { screen -> CGFloat in
            let overlap = screen.frame.intersection(window)
            return overlap.isNull ? 0 : overlap.width * overlap.height
        }
        if let best = overlaps.indices.max(by: { overlaps[$0] < overlaps[$1] }), overlaps[best] > 0 { return best }
        let center = CGPoint(x: window.midX, y: window.midY)
        return screens.firstIndex { $0.frame.contains(center) } ?? 0
    }

    private static func setFrame(_ frame: CGRect, of window: AXUIElement, app: AXUIElement) -> Bool {
        // VoiceOver and Chromium apps turn this on; it animates and breaks programmatic resizes.
        let enhanced = AX.bool(app, enhancedUIAttribute) == true
        if enhanced { AX.set(app, enhancedUIAttribute, NSNumber(value: false)) }
        defer { if enhanced { AX.set(app, enhancedUIAttribute, NSNumber(value: true)) } }

        var size = frame.size
        var origin = frame.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size), let originValue = AXValueCreate(.cgPoint, &origin) else { return false }
        // Size first so a move to a smaller display isn't clamped, then position, then size again
        // because AX applies one at a time and may have constrained the first.
        AX.set(window, kAXSizeAttribute, sizeValue)
        let moved = AX.set(window, kAXPositionAttribute, originValue)
        let resized = AX.set(window, kAXSizeAttribute, sizeValue)
        return moved || resized
    }
}
