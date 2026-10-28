import HaloCore
import SwiftUI

/// The animated progress values both themes draw from. `RingView` owns and animates them; the
/// themes derive every position, size and fade from them, so a retargeted spring moves
/// everything together.
struct RingStage {
    /// Appear/dismiss: 0 collapsed into the centre … 1 shown (briefly above 1 while settling).
    var appear: Double
    /// The ring is appearing from collapsed (not reopening mid-dismiss), so Glass segments grow
    /// one after another.
    var staggersAppear: Bool
    /// Folder fans on screen: the open folder's, plus any still folding away.
    var fans: [FanLayer]
    /// Called when a fan layer's view appears, to start unfolding it out of its folder.
    var unfold: (FanLayer.ID) -> Void

    /// The fan of the open folder, whose children are the model's current level.
    var openFan: FanLayer? { fans.last(where: \.isOpen) }
}

/// One folder's children fanned out on the outer arc (live overlay only).
struct FanLayer: Identifiable {
    /// The folder's path: the root slot, then each nested folder's slot among its parent's
    /// children.
    var id: [Int]
    var ring: Ring
    var arc: ArcGeometry
    /// Direction of the folder slot the children grow out of.
    var sourceAngle: Double
    /// True when that folder is a root slot; false for a folder among its parent's children (on
    /// the arc).
    var sourceIsRootSlot: Bool
    /// 0 folded into the folder … 1 fanned out.
    var progress: Double
    /// False while folding away; the layer is removed once folded.
    var isOpen: Bool
}

extension RingViewModel {
    /// The fan of the folder open now, folded (progress 0), or nil when none is fanned out.
    var currentFan: FanLayer? {
        guard let arc = childArc, let anchor = folderAnchor, let root = rootRing, let entry = levelStack.last else { return nil }
        let nested = levelStack.count > 1
        let sourceAngle = nested
            ? ArcGeometry(count: entry.ring.slotCount, centerAngle: arc.centerAngle, step: metrics.childStep).angle(of: entry.slot)
            : RingGeometry(slotCount: root.slotCount).centerAngle(of: anchor)
        return FanLayer(id: levelStack.map(\.slot), ring: ring, arc: arc, sourceAngle: sourceAngle,
                        sourceIsRootSlot: !nested, progress: 0, isOpen: true)
    }
}

/// Keeps `RingView`'s fan layers in step with the model's level: the newly opened folder's
/// children unfold while the previous folder's fold away, each layer on its own spring. Opening
/// a folder that is still folding reverses it from where it is.
struct FanDirector {
    var layers: [FanLayer]

    init(model: RingViewModel) {
        layers = model.currentFan.map { [Self.settled($0)] } ?? []
    }

    private static func settled(_ layer: FanLayer) -> FanLayer {
        var layer = layer
        layer.progress = 1
        return layer
    }

    /// What a level change asks the caller to animate.
    struct Change {
        /// Layers that start folding into their folders.
        var folding: [FanLayer.ID] = []
        /// A layer that was folding and is open again: spring it back out from where it is.
        /// (A new layer unfolds once its view appears, so it starts folded.)
        var reopened: FanLayer.ID?
    }

    /// Updates the layers after the model's level changed to `target`'s; `restart` (a new ring,
    /// or no animation) shows it settled at once.
    mutating func levelChanged(to target: FanLayer?, restart: Bool) -> Change {
        if restart {
            layers = target.map { [Self.settled($0)] } ?? []
            return Change()
        }
        var change = Change()
        for i in layers.indices where layers[i].isOpen && layers[i].id != target?.id {
            layers[i].isOpen = false
            change.folding.append(layers[i].id)
        }
        guard let target else { return change }
        if let i = layers.firstIndex(where: { $0.id == target.id }) {
            layers[i].ring = target.ring
            layers[i].arc = target.arc
            if !layers[i].isOpen {
                layers[i].isOpen = true
                change.reopened = target.id
            }
        } else {
            layers.append(target)
        }
        return change
    }

    mutating func setProgress(_ progress: Double, of id: FanLayer.ID) {
        guard let i = layers.firstIndex(where: { $0.id == id }) else { return }
        layers[i].progress = progress
    }

    /// Opens a layer fully (once its view is on screen); folding layers are left alone.
    mutating func unfold(_ id: FanLayer.ID) {
        guard let i = layers.firstIndex(where: { $0.id == id && $0.isOpen }) else { return }
        layers[i].progress = 1
    }

    /// Drops a layer that has finished folding (unless it was reopened meanwhile).
    mutating func removeFolded(_ id: FanLayer.ID) {
        layers.removeAll { $0.id == id && !$0.isOpen }
    }
}
