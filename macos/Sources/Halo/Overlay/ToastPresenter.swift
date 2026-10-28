import AppKit
import HaloCore
import SwiftUI

/// A small, non-activating HUD near the pointer for action feedback ("Copied", "Needs
/// Accessibility permission" with a button, errors). Auto-dismisses.
///
/// The toast floats in an `OverlayPanel` like the ring, so it never takes focus. A new toast
/// replaces the one showing. Hovering pauses the countdown; clicking the button runs it and
/// dismisses, clicking anywhere else on the toast dismisses it.
final class ToastPresenter {
    static let shared = ToastPresenter()

    enum Style { case info, success, warning, error }

    struct Button {
        var title: String
        var action: () -> Void
    }

    /// Widest a toast gets (margins included); longer messages wrap.
    private static let maxWidth: CGFloat = 460
    /// Where the toast sits relative to its anchor (usually the ring's centre).
    private static let offsetBelowAnchor: CGFloat = 90
    /// Countdown left after the pointer leaves a hovered toast, at least.
    private static let afterHover: TimeInterval = 1.2

    private let model = ToastModel()
    private var button: Button?
    private var dismissTask: Task<Void, Never>?
    private var orderOutTask: Task<Void, Never>?
    private var dismissAt: Date?
    /// Countdown left while the pointer rests on the toast (paused).
    private var pausedRemaining: TimeInterval?
    private var isHovering = false
    private var buttonPressBegan = false

    private lazy var hostingView = OverlayHostingView(rootView: ToastView(content: Self.emptyContent, model: model))
    /// Created on the first toast.
    private var panel: OverlayPanel?
    /// Measures content at a proposed width (an `NSHostingView` only reports its ideal size).
    private lazy var measurer = NSHostingController(rootView: ToastView(content: Self.emptyContent, model: ToastModel()))

    private static let emptyContent = ToastContent(message: "", symbol: "info.circle.fill", tint: .accentColor)

    private init() {}

    /// Shows a toast `offsetBelowAnchor` points below `anchor` (screen coordinates; the pointer
    /// when nil), clamped to the visible frame of that screen, for `duration` seconds.
    func show(_ message: String, symbol: String? = nil, style: Style = .info, button: Button? = nil, duration: TimeInterval = 2.2, anchor: CGPoint? = nil) {
        Log.overlay.info("Toast: \(message, privacy: .public)")
        let content = ToastContent(message: message, symbol: symbol ?? style.symbol, tint: style.tint, buttonTitle: button?.title)
        self.button = button
        buttonPressBegan = false
        model.isButtonPressed = false
        model.buttonFrame = nil

        let anchor = anchor ?? NSEvent.mouseLocation
        guard let screen = OverlayPlacement.screen(containing: anchor) else { return }
        measurer.rootView = ToastView(content: content, model: ToastModel())
        let fitting = measurer.sizeThatFits(in: CGSize(width: Self.maxWidth, height: screen.frame.height / 2))
        let size = CGSize(width: ceil(fitting.width), height: ceil(fitting.height))
        let frame = OverlayPlacement.frame(size: size, centeredOn: CGPoint(x: anchor.x, y: anchor.y - Self.offsetBelowAnchor), on: screen)

        orderOutTask?.cancel()
        orderOutTask = nil
        let panel = self.panel ?? makePanel()
        self.panel = panel
        hostingView.rootView = ToastView(content: content, model: model)
        panel.setFrame(frame, display: false)
        if panel.isVisible {
            model.isVisible = true
        } else {
            model.isVisible = false
            hostingView.layoutSubtreeIfNeeded()
            panel.orderFrontRegardless()
            // Flip on the next turn so SwiftUI animates from the hidden state.
            Task { [weak self] in self?.model.isVisible = true }
        }

        let spoken = button.map { "\(message) \($0.title) button." } ?? message
        OverlayAnnouncer.announce(spoken, priority: style == .warning || style == .error ? .high : .medium)

        // The panel may have moved under (or away from) a resting pointer without enter/exit events.
        isHovering = frame.contains(NSEvent.mouseLocation)
        if isHovering {
            pausedRemaining = duration
            dismissTask?.cancel()
        } else {
            scheduleDismiss(after: duration)
        }
    }

    /// Hides the toast now (e.g. when the ring opens again).
    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        dismissAt = nil
        pausedRemaining = nil
        guard let panel, panel.isVisible, orderOutTask == nil else { return }
        model.isVisible = false
        model.isButtonPressed = false
        let delay = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.15 : 0.22
        orderOutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            panel.orderOut(nil)
            self.button = nil
            self.isHovering = false
            self.orderOutTask = nil
        }
    }

    // MARK: Countdown

    private func scheduleDismiss(after delay: TimeInterval) {
        dismissTask?.cancel()
        pausedRemaining = nil
        dismissAt = Date(timeIntervalSinceNow: delay)
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func hoverChanged(_ inside: Bool) {
        isHovering = inside
        guard panel?.isVisible == true, orderOutTask == nil else { return }
        if inside {
            pausedRemaining = dismissAt.map { max(0, $0.timeIntervalSinceNow) }
            dismissTask?.cancel()
            dismissTask = nil
        } else {
            scheduleDismiss(after: max(pausedRemaining ?? 0, Self.afterHover))
        }
    }

    // MARK: Clicks

    private func makePanel() -> OverlayPanel {
        let panel = OverlayPanel()
        panel.contentView = hostingView
        panel.interceptor = { [weak self] event in self?.handle(event) ?? false }
        hostingView.onHoverChange = { [weak self] inside in self?.hoverChanged(inside) }
        model.onButton = { [weak self] in self?.pressButton() }
        return panel
    }

    /// Decides clicks in AppKit: SwiftUI buttons are unreliable in a panel that is never key.
    private func handle(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown:
            buttonPressBegan = isOverButton(event)
            model.isButtonPressed = buttonPressBegan
            return true
        case .leftMouseDragged:
            if buttonPressBegan { model.isButtonPressed = isOverButton(event) }
            return true
        case .leftMouseUp:
            let activate = buttonPressBegan && isOverButton(event)
            buttonPressBegan = false
            model.isButtonPressed = false
            if activate { pressButton() } else { dismiss() }
            return true
        case .rightMouseUp:
            dismiss()
            return true
        case .rightMouseDown, .rightMouseDragged, .otherMouseDown, .otherMouseDragged, .otherMouseUp:
            return true
        default:
            return false
        }
    }

    private func isOverButton(_ event: NSEvent) -> Bool {
        guard let frame = model.buttonFrame else { return false }
        var point = hostingView.convert(event.locationInWindow, from: nil)
        if !hostingView.isFlipped { point.y = hostingView.bounds.height - point.y }
        return frame.insetBy(dx: -4, dy: -4).contains(point)
    }

    private func pressButton() {
        let action = button?.action
        dismiss()
        action?()
    }
}

private extension ToastPresenter.Style {
    var symbol: String {
        switch self {
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .info: AppModel.shared.settings.accent.color
        case .success: Color(nsColor: .systemGreen)
        case .warning: Color(nsColor: .systemOrange)
        case .error: Color(nsColor: .systemRed)
        }
    }
}
