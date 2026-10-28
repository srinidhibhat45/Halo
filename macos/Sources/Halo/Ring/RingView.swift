import HaloCore
import SwiftUI

/// Draws the ring described by `model`: its theme (Classic or Glass), slots, highlight, hub,
/// labels, folders and every animation between those states.
///
/// Sized to a `model.metrics.canvasSide` square with the ring centred, on a transparent
/// background; it draws its own shadows. It does no hit-testing (the overlay and editor decide
/// what the pointer is over), but in `.editor` mode each slot is an accessibility element.
///
/// The live overlay draws the Classic theme with Core Animation instead (`ClassicRingLayerView`);
/// this view draws Classic in the configurator and Glass everywhere.
///
/// Motion is driven by a few progress values owned here (`RingStage`): `appear` springs toward
/// `model.isPresented` (live mode; other modes are always shown) and each folder fan springs
/// open or folded as `model.levelID` changes. Springs retarget from wherever they are, so
/// reopening mid-dismiss or switching folders mid-fan continues smoothly. The overlay orders the
/// panel in with `isPresented` false (nothing is drawn), sets it true on the next frame, and
/// orders out `RingMotion.dismissDuration` after clearing it, when the ring has fully collapsed.
struct RingView: View {
    let model: RingViewModel

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.ringMotionFreeze) private var freeze

    /// Appear/dismiss progress (live mode).
    @ViewState private var appear: Double
    @ViewState private var fans: FanDirector
    /// When the ring last started to dismiss, so a reopen before it has collapsed reverses in
    /// place instead of blooming one segment after another.
    @ViewState private var dismissedAt: Date?

    init(model: RingViewModel) {
        self.model = model
        _appear = ViewState(initialValue: model.isPresented ? 1 : 0)
        _fans = ViewState(initialValue: FanDirector(model: model))
    }

    var body: some View {
        let m = model.metrics
        let motion = RingMotion(speed: model.animationSpeed, reduceMotion: reduceMotion)
        let environment = RingEnvironment(
            colorScheme: colorScheme,
            reduceTransparency: reduceTransparency,
            increaseContrast: contrast == .increased,
            differentiateWithoutColor: differentiateWithoutColor,
            motion: motion
        )
        theme(environment, stage: stage(motion))
            // A new editor level rebuilds clockwise, like entering a folder in Logi Options+.
            .id(model.mode == .editor ? model.levelID : 0)
            .modifier(ShakeEffect(progress: CGFloat(model.rejectCount), amplitude: 6 * m.unit))
            .animation(motion.shake, value: model.rejectCount)
            .frame(width: m.canvasSide, height: m.canvasSide)
            .allowsHitTesting(false)
            .modifier(RingAccessibility(model: model))
            .onChange(of: model.isPresented) { _, shown in
                if !shown { dismissedAt = Date() }
                withAnimation(shown ? motion.appear : motion.dismiss) { appear = shown ? 1 : 0 }
            }
            .onChange(of: model.levelID) { levelChanged(motion: motion) }
    }

    @ViewBuilder
    private func theme(_ environment: RingEnvironment, stage: RingStage) -> some View {
        switch model.theme {
        case .classic: ClassicRingView(model: model, environment: environment)
        case .glass: GlassRingView(model: model, environment: environment, stage: stage)
        }
    }

    private func stage(_ motion: RingMotion) -> RingStage {
        var layers = fans.layers
        if let frozen = freeze.fan {
            for i in layers.indices where layers[i].isOpen { layers[i].progress = frozen }
        }
        return RingStage(
            appear: model.mode == .live ? appear : 1,
            // Read when `isPresented` turns true, before `dismissedAt` can change.
            staggersAppear: dismissedAt.map { Date().timeIntervalSince($0) >= RingMotion.dismissDuration(speed: model.animationSpeed) } ?? true,
            fans: layers,
            unfold: { id in withAnimation(motion.fanOut) { fans.unfold(id) } }
        )
    }

    /// Folds the previous folder's fan and unfolds the new one.
    private func levelChanged(motion: RingMotion) {
        let restart = model.levelTransition == .none || motion.isInstant
        var transaction = Transaction()
        transaction.disablesAnimations = true
        var change = FanDirector.Change()
        withTransaction(transaction) {
            change = fans.levelChanged(to: model.currentFan, restart: restart)
        }
        for id in change.folding {
            withAnimation(motion.fanIn, completionCriteria: .logicallyComplete) {
                fans.setProgress(0, of: id)
            } completion: {
                fans.removeFolded(id)
            }
        }
        if let id = change.reopened {
            withAnimation(motion.fanOut) { fans.setProgress(1, of: id) }
        }
    }
}

/// Editor: the ring contains one element per slot. Live: one element naming the highlight.
/// Preview: decorative (its container describes it).
private struct RingAccessibility: ViewModifier {
    let model: RingViewModel

    func body(content: Content) -> some View {
        switch model.mode {
        case .editor:
            content
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Ring")
        case .live:
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Action ring")
                .accessibilityValue(highlightedTitle)
        case .preview:
            content.accessibilityHidden(true)
        }
    }

    private var highlightedTitle: String {
        guard let index = model.highlighted, model.ring.slots.indices.contains(index) else { return "" }
        return model.ring.slots[index].displayTitle
    }
}
