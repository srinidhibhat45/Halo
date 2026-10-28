import HaloCore
import SwiftUI

// MARK: - Nested ring

/// A preview of the nested ring, its slot count, and a button to open it in the editor.
struct FolderActionEditor: View {
    @Binding var ring: Ring
    let onOpen: () -> Void

    @ViewState private var pendingSlotCount: Int?

    var body: some View {
        HStack(spacing: 14) {
            MiniRingPreview(ring: ring)
                .frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 8) {
                Text("\(ring.filledCount) of \(ring.slotCount) slots used")
                    .foregroundStyle(.secondary)
                Button("Open Nested Ring", systemImage: "arrow.down.right.circle", action: onOpen)
            }
        }
        .padding(.vertical, 2)
        Picker("Slots", selection: slotCount) {
            ForEach(Array(Ring.slotRange), id: \.self) { count in
                Text("\(count)").tag(count)
            }
        }
        .modifier(SlotCountConfirmation(pendingCount: $pendingSlotCount, filledCount: ring.filledCount, onConfirm: resize))
    }

    /// Shrinking past the filled slots asks first, as the toolbar's slot count does.
    private var slotCount: Binding<Int> {
        Binding(
            get: { ring.slotCount },
            set: { count in
                if ring.editorActionsLost(resizingTo: count) > 0 {
                    pendingSlotCount = count
                } else {
                    resize(count)
                }
            }
        )
    }

    private func resize(_ count: Int) {
        var resized = ring
        resized.resize(to: count)
        ring = resized
    }
}

/// A small static drawing of a ring's icons, for the nested-ring inspector.
struct MiniRingPreview: View {
    let ring: Ring

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let geometry = RingGeometry(slotCount: ring.slotCount)
            let radius = side * 0.36
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: side * 0.22)
                    .frame(width: radius * 2, height: radius * 2)
                ForEach(Array(ring.slots.enumerated()), id: \.element.id) { index, slot in
                    let offset = geometry.offset(of: index, radius: Double(radius))
                    IconView(spec: slot.displayIcon, size: side * 0.15, symbolColor: .secondary)
                        .position(x: side / 2 + offset.x, y: side / 2 + offset.y)
                }
            }
            .frame(width: side, height: side)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Nested ring with \(ring.filledCount) of \(ring.slotCount) slots used")
    }
}

// MARK: - Smart Action

/// The ordered steps of a Smart Action: add from the catalog, reorder, delete, set each step's
/// delay, and edit each step with the same editors as a slot.
struct MacroActionEditor: View {
    @Binding var macro: Macro
    @ViewState private var expanded: Set<MacroStep.ID> = []

    var body: some View {
        Section {
            if macro.steps.isEmpty {
                Text("No steps yet. Add the actions to run, in order.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(macro.steps.enumerated()), id: \.element.id) { index, step in
                MacroStepRow(
                    step: stepBinding(step.id, fallback: step),
                    number: index + 1,
                    canMoveUp: index > 0,
                    canMoveDown: index < macro.steps.count - 1,
                    isExpanded: expansion(step.id),
                    onMove: { move(step.id, by: $0) },
                    onDelete: { delete(step.id) }
                )
            }
            addStepMenu
        } header: {
            Text("Steps")
        } footer: {
            Text("Steps run one after another. Each step can wait before the next one starts, for example while an app opens.")
        }
    }

    private var addStepMenu: some View {
        Menu {
            ForEach(ActionCategory.allCases.filter { $0 != .folders && $0 != .macros }) { category in
                Menu {
                    ForEach(ActionCatalog.templates(in: category)) { template in
                        Button(template.title, systemImage: template.symbol) { add(template) }
                    }
                } label: {
                    Label(category.title, systemImage: category.symbol)
                }
            }
        } label: {
            Label("Add Step", systemImage: "plus")
        }
        .fixedSize()
    }

    private func stepBinding(_ id: MacroStep.ID, fallback: MacroStep) -> Binding<MacroStep> {
        let macro = $macro
        return Binding(
            get: { macro.wrappedValue.steps.first { $0.id == id } ?? fallback },
            set: { newValue in
                guard let i = macro.wrappedValue.steps.firstIndex(where: { $0.id == id }) else { return }
                var updated = macro.wrappedValue
                updated.steps[i] = newValue
                macro.wrappedValue = updated
            }
        )
    }

    private func expansion(_ id: MacroStep.ID) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { open in
                if open { expanded.insert(id) } else { expanded.remove(id) }
            }
        )
    }

    private func add(_ template: ActionTemplate) {
        let step = MacroStep(action: template.action)
        var updated = macro
        updated.steps.append(step)
        macro = updated
        if template.needsSetup { expanded.insert(step.id) }
    }

    private func move(_ id: MacroStep.ID, by offset: Int) {
        guard let i = macro.steps.firstIndex(where: { $0.id == id }), macro.steps.indices.contains(i + offset) else { return }
        var updated = macro
        updated.steps.swapAt(i, i + offset)
        macro = updated
    }

    private func delete(_ id: MacroStep.ID) {
        var updated = macro
        updated.steps.removeAll { $0.id == id }
        macro = updated
        expanded.remove(id)
    }
}

/// One step: a summary row that expands into the step's action type, details and delay.
private struct MacroStepRow: View {
    @Binding var step: MacroStep
    let number: Int
    let canMoveUp: Bool
    let canMoveDown: Bool
    @Binding var isExpanded: Bool
    let onMove: (Int) -> Void
    let onDelete: () -> Void

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            LabeledContent("Action") {
                ActionTypeMenu(current: step.action.kind, excluded: [.folder, .macro]) { kind in
                    step.action = kind.editorDefaultAction
                }
            }
            ActionDetailsEditor(action: $step.action, setup: .constant(false), onOpenFolder: nil, inSections: false)
            Stepper(value: $step.delayAfter, in: 0...10, step: 0.05) {
                LabeledContent("Then Wait", value: "\(delayText) s")
            }
            .accessibilityValue("\(delayText) seconds")
        } label: {
            HStack(spacing: 8) {
                Text("\(number)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .frame(width: 20, height: 20)
                    .background(.quaternary, in: Circle())
                    .accessibilityHidden(true)
                IconView(spec: step.action.defaultIcon, size: 16, symbolColor: .accentColor)
                Text(step.action.defaultTitle)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if step.delayAfter > 0 {
                    Text("then \(delayText) s")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Menu {
                    Button("Move Up", systemImage: "arrow.up") { onMove(-1) }
                        .disabled(!canMoveUp)
                    Button("Move Down", systemImage: "arrow.down") { onMove(1) }
                        .disabled(!canMoveDown)
                    Divider()
                    Button("Delete Step", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Step \(number) options")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Step \(number): \(step.action.defaultTitle)")
            .accessibilityActions {
                if canMoveUp { Button("Move Up") { onMove(-1) } }
                if canMoveDown { Button("Move Down") { onMove(1) } }
                Button("Delete Step", action: onDelete)
            }
        }
    }

    private var delayText: String {
        step.delayAfter.formatted(.number.precision(.fractionLength(0...2)))
    }
}
