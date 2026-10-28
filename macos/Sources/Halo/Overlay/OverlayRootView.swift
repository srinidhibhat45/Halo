import AppKit
import HaloCore
import Observation
import SwiftUI

/// The ring panel's content view: the Core Animation Classic ring (`ClassicRingLayerView`) for
/// the Classic theme, the SwiftUI `RingView` (Glass) otherwise, switching when the theme
/// setting changes. Each is made the first time it is needed and kept; only the one showing is
/// in the window, so the other does no work.
final class OverlayRingContentView: NSView {
    private let model: RingViewModel
    private var classic: ClassicRingLayerView?
    private var hosting: OverlayHostingView<OverlayRootView>?
    /// The theme is being observed (one observation at a time, re-armed after it fires).
    private var isObserving = false

    init(model: RingViewModel) {
        self.model = model
        super.init(frame: .zero)
        showCurrentTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        showCurrentTheme()
        super.layout()
    }

    /// Puts the current theme's view in place and watches the theme for the next switch.
    private func showCurrentTheme() {
        let theme: RingTheme
        if isObserving {
            theme = model.theme
        } else {
            isObserving = true
            theme = withObservationTracking { model.theme } onChange: { [weak self] in
                MainActor.assumeIsolated {
                    self?.isObserving = false
                    self?.needsLayout = true
                }
            }
        }
        let content: NSView
        switch theme {
        case .classic:
            let view = classic ?? ClassicRingLayerView(model: model)
            classic = view
            content = view
        case .glass:
            let view = hosting ?? OverlayHostingView(rootView: OverlayRootView(model: model))
            hosting = view
            content = view
        }
        content.frame = bounds
        guard content.superview !== self else { return }
        subviews.forEach { $0.removeFromSuperview() }
        content.autoresizingMask = [.width, .height]
        addSubview(content)
    }
}

/// The SwiftUI ring in the panel: centred (the panel may be larger than the current level's
/// canvas when a nested ring has more slots), drawn as if its window were active so Liquid Glass
/// doesn't dim in a panel that is never key.
struct OverlayRootView: View {
    let model: RingViewModel

    var body: some View {
        RingView(model: model)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.appearsActive, true)
    }
}
