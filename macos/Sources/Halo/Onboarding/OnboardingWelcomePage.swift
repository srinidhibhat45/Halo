import HaloCore
import SwiftUI

/// Step 1: the user's own ring, alive (the highlight walks around it, or follows the pointer),
/// next to a short pitch.
struct OnboardingWelcomePage: View {
    /// Side of the square the ring preview fills, in points.
    private static let ringSide: CGFloat = 310

    @ViewState private var ring = Self.makeRingModel()
    @ViewState private var isPointerOverRing = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 40) {
            ringPreview
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Welcome to Halo")
                        .font(.system(size: 34, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Your favourite actions in a ring around the pointer, one press away.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 16) {
                    feature("cursorarrow.click.2", "Opens where you are",
                            "Press a shortcut or a mouse button and the ring appears around the pointer.")
                    feature("hand.draw", "Click or flick",
                            "Tap to keep the ring open and click, or hold, flick toward an action and let go.")
                    feature("app.badge", "A ring for every app",
                            "Give apps their own actions, and tuck more into nested rings.")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Ring

    /// The ring, centred in a `ringSide` square. Its canvas is larger (room for folders that
    /// never open here), so the transparent rest overflows the square and ignores the pointer.
    private var ringPreview: some View {
        let accent = ring.accent.color
        return ZStack {
            Circle()
                .fill(RadialGradient(colors: [accent.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: Self.ringSide / 2))
                .accessibilityHidden(true)
            RingView(model: ring)
                .frame(width: ring.metrics.canvasSide, height: ring.metrics.canvasSide)
                .allowsHitTesting(false)
        }
        .frame(width: Self.ringSide, height: Self.ringSide)
        .contentShape(Circle())
        .onContinuousHover { phase in followPointer(phase) }
        .task(id: isPointerOverRing) {
            if !isPointerOverRing { await cycleHighlight() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your ring")
        .accessibilityValue(actionNames)
    }

    /// Highlights the slot under the pointer, the way the real ring does in tap mode.
    private func followPointer(_ phase: HoverPhase) {
        switch phase {
        case .active(let point):
            isPointerOverRing = true
            let center = Self.ringSide / 2
            let target = ring.hitTest(dx: point.x - center, dy: point.y - center, holding: false, current: ring.highlighted)
            if case .slot(let index) = target, !ring.ring.slots[index].isEmpty {
                ring.highlighted = index
            } else {
                ring.highlighted = nil
            }
        case .ended:
            isPointerOverRing = false
        }
    }

    /// Walks the highlight clockwise over the filled slots until cancelled.
    private func cycleHighlight() async {
        let filled = ring.ring.slots.indices.filter { !ring.ring.slots[$0].isEmpty }
        guard !filled.isEmpty else { return }
        var position = ring.highlighted.flatMap { filled.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        while !Task.isCancelled {
            ring.highlighted = filled[position % filled.count]
            position += 1
            try? await Task.sleep(for: .seconds(reduceMotion ? 2 : 1.2))
        }
    }

    private var actionNames: String {
        let names = ring.ring.slots.filter { !$0.isEmpty }.map(\.displayTitle)
        return names.isEmpty ? "No actions yet" : names.formatted(.list(type: .and))
    }

    /// A preview of the user's global ring, scaled so the ring and its tooltip fill `ringSide`.
    private static func makeRingModel() -> RingViewModel {
        let config = AppModel.shared.config
        let model = RingViewModel(mode: .preview, ring: config.globalRing, settings: config.settings)
        let extent = RingMetrics(theme: model.theme, scale: 1, slotCount: model.ring.slotCount).clampRadius * 2
        if extent > 0 { model.scale = Double(ringSide / extent) }
        return model
    }

    // MARK: Pitch

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
