import AppKit

/// Where overlay windows go: the screen under a point, the part of it windows may use, and
/// frames moved inside that part.
enum OverlayPlacement {
    /// Gap kept between an overlay and the edges of the usable area.
    static let margin: CGFloat = 8

    /// The screen containing `point` (screen coordinates). Edges are inclusive, unlike
    /// `NSMouseInRect`; `NSScreen.main` is the key window's screen, not the pointer's.
    static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { screen in
            let f = screen.frame
            return point.x >= f.minX && point.x <= f.maxX && point.y >= f.minY && point.y <= f.maxY
        } ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// The visible frame (menu bar and Dock excluded), also kept below the camera housing.
    static func usableFrame(of screen: NSScreen) -> CGRect {
        var frame = screen.visibleFrame
        let top = screen.frame.maxY - screen.safeAreaInsets.top
        if frame.maxY > top { frame.size.height = max(0, top - frame.minY) }
        return frame
    }

    /// A rect of `size` centred on `center`, moved (never resized) to lie inside the usable
    /// area of `screen` with `margin` to spare, and aligned to the screen's pixels. On an axis
    /// where it can't fit, it is centred in the usable area.
    static func frame(size: CGSize, centeredOn center: CGPoint, on screen: NSScreen) -> CGRect {
        let bounds = usableFrame(of: screen).insetBy(dx: margin, dy: margin)
        func origin(_ center: CGFloat, _ length: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
            guard length < high - low else { return (low + high - length) / 2 }
            return min(max(center - length / 2, low), high - length)
        }
        let rect = CGRect(x: origin(center.x, size.width, bounds.minX, bounds.maxX),
                          y: origin(center.y, size.height, bounds.minY, bounds.maxY),
                          width: size.width, height: size.height)
        return screen.backingAlignedRect(rect, options: .alignAllEdgesNearest)
    }
}
