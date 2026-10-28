import AppKit
import HaloCore
import SwiftUI

/// The editor's interactive ring: the real `RingView` (editor mode) with invisible per-slot hit
/// regions on top for clicks, context menus and dragging, one drop target for the whole ring,
/// the Add to Ring picker's anchor, and keyboard navigation.
///
/// Clicking an empty slot opens the picker there; clicking a filled one selects it for the
/// inspector, and double-clicking replaces it (or opens a nested ring).
///
/// Hover, clicks and drops are resolved with the same geometry the overlay uses
/// (`RingViewModel.hitTest`), so what lights up is what gets edited.
struct RingEditorCanvas: View {
    let session: RingEditorSession

    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let model = session.canvas
            let metrics = model.metrics
            ZStack {
                focusHalo(metrics: metrics, center: center)
                RingView(model: model)
                    .frame(width: metrics.canvasSide, height: metrics.canvasSide)
                    .position(center)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                ForEach(Array(session.ring.slots.enumerated()), id: \.element.id) { index, slot in
                    SlotHitRegion(
                        session: session,
                        index: index,
                        slot: slot,
                        sector: sector(index, metrics: metrics, center: center, limit: min(size.width, size.height) / 2),
                        onActivate: { isFocused = true }
                    )
                }
                HubHitRegion(session: session, radius: metrics.hubRadius, center: center) { isFocused = true }
                PickerAnchorView(session: session, center: center)
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture {
                isFocused = true
                session.select(nil)
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    let slot = slot(at: point, center: center, current: model.highlighted)
                    if model.highlighted != slot { model.highlighted = slot }
                case .ended:
                    if model.highlighted != nil { model.highlighted = nil }
                }
            }
            .dropDestination(for: RingDropItem.self) { items, drop in
                // The slot that glowed is the one that gets it (hover hysteresis included).
                let index = model.dropTarget ?? slot(at: drop.location, center: center, current: nil)
                model.dropTarget = nil
                model.dragSource = nil
                guard let index, let resolved = items.first?.resolved else { return }
                handleDrop(resolved, on: index)
            }
            .onDropSessionUpdated { drop in
                switch drop.phase {
                case .entering, .active:
                    let target = slot(at: drop.location, center: center, current: model.dropTarget)
                    if model.dropTarget != target { model.dropTarget = target }
                default:
                    if model.dropTarget != nil { model.dropTarget = nil }
                }
            }
            .sensoryFeedback(.alignment, trigger: model.dropTarget) { _, new in
                new != nil && session.model.settings.hapticsEnabled
            }
            .onChange(of: size, initial: true) { _, newSize in session.fit(to: newSize) }
            .onChange(of: model.theme) { session.fit(to: size) }
            .onChange(of: model.ring.slotCount) { session.fit(to: size) }
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onMoveCommand { direction in
            switch direction {
            case .up: session.moveSelection(toward: .up)
            case .down: session.moveSelection(toward: .down)
            case .left: session.moveSelection(toward: .left)
            case .right: session.moveSelection(toward: .right)
            @unknown default: break
            }
        }
        .onDeleteCommand {
            if let index = session.selectedIndex { session.clear(at: index) }
        }
        .onExitCommand {
            if session.isNested { session.goBack() } else { session.select(nil) }
        }
        .onKeyPress(.return) {
            let index = session.selectedIndex ?? session.ring.slots.firstIndex(where: \.isEmpty) ?? 0
            if session.ring[index].isEmpty {
                session.openPicker(at: index, from: .canvas)
            } else {
                session.edit(index)
            }
            return .handled
        }
        .onKeyPress(keys: [.tab, KeyEquivalent("\u{19}")], phases: .down) { press in
            let forward = press.key == .tab && !press.modifiers.contains(.shift)
            return session.cycleSelection(forward: forward) ? .handled : .ignored
        }
        .onKeyPress(characters: .decimalDigits, phases: .down) { press in
            guard press.modifiers.isEmpty, let digit = Int(press.characters) else { return .ignored }
            let index = digit == 0 ? 9 : digit - 1
            guard index < session.ring.slotCount else { return .ignored }
            session.select(index)
            return .handled
        }
        .onChange(of: session.focusRequest, initial: true) { _, request in
            guard request == .canvas else { return }
            session.focusRequest = nil
            isFocused = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(session.levels.last?.title ?? "Ring") ring")
        .accessibilityHint("Use the arrow keys to choose a slot, Return to add to it or edit it, Delete to clear it.")
    }

    /// A soft ring around the slots while the canvas has keyboard focus.
    @ViewBuilder
    private func focusHalo(metrics: RingMetrics, center: CGPoint) -> some View {
        if isFocused {
            let radius = metrics.outerRadius * metrics.highlightScale + 14
            Circle()
                .strokeBorder(Color.accentColor.opacity(contrast == .increased ? 1 : 0.45), style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
                .frame(width: radius * 2, height: radius * 2)
                .position(center)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func slot(at point: CGPoint, center: CGPoint, current: Int?) -> Int? {
        let hit = session.canvas.hitTest(dx: Double(point.x - center.x), dy: Double(point.y - center.y), holding: false, current: current)
        if case .slot(let index) = hit { return index }
        return nil
    }

    /// The hit region of slot `index`: its whole sector from the hub out to `maxHitRadius`, kept
    /// inside the canvas (`limit`) so it never covers the breadcrumb or footer.
    private func sector(_ index: Int, metrics: RingMetrics, center: CGPoint, limit: CGFloat) -> EditorSlotSector {
        let (start, end) = session.canvas.geometry.sector(of: index)
        return EditorSlotSector(center: center, innerRadius: metrics.hubRadius, outerRadius: max(metrics.hubRadius + 1, min(metrics.maxHitRadius, limit)),
                                startAngle: start, endAngle: end)
    }

    private func handleDrop(_ resolved: RingDropItem.Resolved, on index: Int) {
        isFocused = true
        switch resolved {
        case .slot(let id):
            guard let source = session.ring.index(of: id), source != index else { return }
            if NSEvent.modifierFlags.contains(.option) {
                session.copy(source, onto: index)
            } else {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { session.swap(source, index) }
            }
        case .content(let slot, let needsSetup):
            session.assign(slot, at: index, needsSetup: needsSetup)
        }
    }
}

/// The surface behind the canvas column: opaque window colour with a faint pool of the ring's
/// accent around the ring (which also gives Glass something to refract). Opaque, so it looks the
/// same in the window and in snapshots.
struct CanvasBackdrop: View {
    let accent: Color
    let ringRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let strength = reduceTransparency ? 0 : (colorScheme == .dark ? 0.14 : 0.08)
        Rectangle()
            .fill(Color(nsColor: .windowBackgroundColor))
            .overlay {
                RadialGradient(
                    colors: [accent.opacity(strength), accent.opacity(strength * 0.45), accent.opacity(0)],
                    center: .center, startRadius: ringRadius * 0.2, endRadius: ringRadius * 2.1
                )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// An invisible view on the slot the Add to Ring picker is open for, so the popover points at
/// it and opens away from the ring.
private struct PickerAnchorView: View {
    let session: RingEditorSession
    let center: CGPoint

    var body: some View {
        let model = session.canvas
        let index = session.picker?.anchor == .canvas ? session.pickerIndex : nil
        let offset = index.map(model.slotOffset) ?? .zero
        let side = model.metrics.slotSize
        Color.clear
            .frame(width: side, height: side)
            .popover(isPresented: session.pickerBinding(for: .canvas), arrowEdge: offset.x < -1 ? .leading : .trailing) {
                RingPickerPopover(session: session)
            }
            .position(x: center.x + offset.x, y: center.y + offset.y)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// An annular sector around `center` (in the shape's own coordinates), y-down angles as in
/// `RingGeometry`.
nonisolated struct EditorSlotSector: Shape {
    var center: CGPoint
    var innerRadius: CGFloat
    var outerRadius: CGFloat
    var startAngle: Double
    var endAngle: Double

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.minX + center.x, y: rect.minY + center.y)
        var path = Path()
        path.addArc(center: c, radius: outerRadius, startAngle: .radians(startAngle), endAngle: .radians(endAngle), clockwise: false)
        path.addArc(center: c, radius: innerRadius, startAngle: .radians(endAngle), endAngle: .radians(startAngle), clockwise: true)
        path.closeSubpath()
        return path
    }

    /// Bounding box in the coordinates `center` is given in.
    var bounds: CGRect { path(in: .zero).boundingRect }

    /// The same sector re-centred for a view whose frame is `bounds`.
    var local: EditorSlotSector {
        var copy = self
        copy.center = CGPoint(x: center.x - bounds.minX, y: center.y - bounds.minY)
        return copy
    }
}

/// The invisible, sector-shaped target for one slot: click an empty slot to add to it, click a
/// filled one to select it, double-click to replace it (or open a nested ring), right-click for
/// the slot menu, drag to swap.
private struct SlotHitRegion: View {
    let session: RingEditorSession
    let index: Int
    let slot: Slot
    let sector: EditorSlotSector
    let onActivate: () -> Void

    var body: some View {
        let frame = sector.bounds
        Color.clear
            .frame(width: frame.width, height: frame.height)
            .contentShape(sector.local)
            .onTapGesture {
                onActivate()
                click(count: NSApp.currentEvent?.clickCount ?? 1)
            }
            .contextMenu {
                SlotContextMenu(session: session, index: index)
            }
            .modifier(SlotDragSource(session: session, index: index, slot: slot))
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(session.selectedIndex == index ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { click(count: 1) }
            .accessibilityAction(named: slot.isEmpty ? "Add App or Action" : "Replace") {
                session.openPicker(at: index, from: .canvas)
            }
            .accessibilityActions {
                if slot.action?.isFolder == true {
                    Button("Open Nested Ring") { session.enterFolder(at: index) }
                }
                if !slot.isEmpty {
                    Button("Edit") { session.edit(index) }
                    Button("Duplicate to Next Empty Slot") { session.duplicate(at: index) }
                    Button("Clear") { session.clear(at: index) }
                }
            }
            .position(x: frame.midX, y: frame.midY)
    }

    private func click(count: Int) {
        if slot.isEmpty {
            session.openPicker(at: index, from: .canvas)
        } else if count >= 2 {
            if slot.action?.isFolder == true {
                session.enterFolder(at: index)
            } else {
                session.openPicker(at: index, from: .canvas)
            }
        } else {
            session.select(index)
        }
    }

    private var accessibilityLabel: String {
        let position = "Slot \(index + 1), \(session.direction(of: index))"
        guard let action = slot.action else {
            if let inherited = session.inheritedSlot(at: index) {
                return "\(position), empty, shows \(inherited.displayTitle) from Everywhere"
            }
            return "\(position), empty"
        }
        if case .folder(let ring) = action {
            return "\(position), \(slot.displayTitle), nested ring with \(ring.filledCount) actions"
        }
        return "\(position), \(slot.displayTitle)"
    }
}

/// Filled slots drag onto other slots to swap (⌥ to copy); the dragged slot is drawn lifted.
private struct SlotDragSource: ViewModifier {
    let session: RingEditorSession
    let index: Int
    let slot: Slot

    func body(content: Content) -> some View {
        if slot.isEmpty {
            content
        } else {
            content
                .draggable(EditorDragToken.slot(slot.id)) {
                    SlotDragPreview(slot: slot)
                }
                .onDragSessionUpdated { drag in
                    let model = session.canvas
                    switch drag.phase {
                    case .initial, .active:
                        if model.dragSource != index { model.dragSource = index }
                    default:
                        if model.dragSource != nil { model.dragSource = nil }
                    }
                }
        }
    }
}

/// The centre hub: back out of a nested ring, or clear the selection at the root.
private struct HubHitRegion: View {
    let session: RingEditorSession
    let radius: CGFloat
    let center: CGPoint
    let onActivate: () -> Void

    var body: some View {
        Circle()
            .fill(.clear)
            .frame(width: radius * 2, height: radius * 2)
            .contentShape(Circle())
            .onTapGesture {
                onActivate()
                if session.isNested { session.goBack() } else { session.select(nil) }
            }
            .accessibilityElement()
            .accessibilityLabel("Back to \(session.levels.dropLast().last?.title ?? "the previous ring")")
            .accessibilityAddTraits(.isButton)
            .accessibilityHidden(!session.isNested)
            .position(center)
    }
}

/// The slot's menu on the canvas.
struct SlotContextMenu: View {
    let session: RingEditorSession
    let index: Int

    var body: some View {
        let ring = session.ring
        let slot = ring.slots.indices.contains(index) ? ring[index] : Slot()
        let isFolder = slot.action?.isFolder == true

        Button(slot.isEmpty ? "Add App or Action…" : "Replace…", systemImage: slot.isEmpty ? "plus.circle" : "arrow.left.arrow.right") {
            session.openPicker(at: index, from: .canvas)
        }
        if !slot.isEmpty {
            Button("Edit…", systemImage: "slider.horizontal.3") {
                session.edit(index)
            }
        }
        if isFolder {
            Button("Open Nested Ring", systemImage: "arrow.down.right.circle") {
                session.enterFolder(at: index)
            }
        }
        Divider()
        Button("Duplicate to Next Empty Slot", systemImage: "plus.square.on.square") {
            session.duplicate(at: index)
        }
        .disabled(slot.isEmpty || session.nextEmptySlot(after: index) == nil)
        Button(slot.isEmpty ? "Make Nested Ring" : "Convert to Nested Ring", systemImage: "circle.grid.cross") {
            session.convertToFolder(at: index)
        }
        .disabled(isFolder)
        Menu("Move To", systemImage: "arrow.right.circle") {
            Section("Swap With") {
                ForEach(Array(ring.slots.enumerated()).filter { $0.offset != index }, id: \.element.id) { other, otherSlot in
                    Button("\(other + 1). \(otherSlot.isEmpty ? "Empty (\(session.direction(of: other)))" : otherSlot.displayTitle)") {
                        session.swap(index, other)
                    }
                }
            }
            let destinations = session.moveDestinations(for: index)
            if !destinations.isEmpty {
                Section("Move Into") {
                    ForEach(destinations) { destination in
                        Button(destination.hasRoom ? destination.title : "\(destination.title) (Full)", systemImage: destination.symbol) {
                            session.move(index, to: destination)
                        }
                        .disabled(!destination.hasRoom)
                    }
                }
            }
        }
        .disabled(slot.isEmpty)
        Divider()
        Button("Clear", systemImage: "trash", role: .destructive) {
            session.clear(at: index)
        }
        .disabled(slot.isEmpty)
    }
}

/// The image under the pointer while dragging a slot.
private struct SlotDragPreview: View {
    let slot: Slot

    var body: some View {
        IconView(spec: slot.displayIcon, size: 26)
            .frame(width: 48, height: 48)
            .background(.regularMaterial, in: Circle())
            .overlay(Circle().strokeBorder(.separator))
    }
}
