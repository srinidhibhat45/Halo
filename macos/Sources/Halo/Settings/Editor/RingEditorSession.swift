import AppKit
import HaloCore
import Observation
import SwiftUI

/// State and operations of one ring editor: which ring and folder level is shown, which slot is
/// selected, the Add to Ring picker, and every edit (each one a named, undoable step through
/// `model`).
///
/// Folder navigation and selection are tracked by slot id rather than index, so they follow
/// slots through swaps, moves and undo. `sync()` re-reads the model and repairs both whenever
/// the configuration changes.
@Observable
final class RingEditorSession {
    /// Where keyboard focus should go next; the canvas and inspector consume the request.
    enum FocusRequest: Equatable {
        case canvas
        case inspector
    }

    /// Where the Add to Ring picker is anchored.
    enum PickerAnchor: Equatable {
        /// At the slot on the ring.
        case canvas
        /// At the inspector's Add / Replace button.
        case inspector
    }

    /// The Add to Ring picker, open for one slot.
    struct PickerRequest: Equatable {
        var slotID: Slot.ID
        var anchor: PickerAnchor
    }

    /// A ring (or folder) a slot can be moved into from the context menu.
    struct MoveDestination: Identifiable, Hashable {
        var target: RingTarget
        var path: [Int]
        var title: String
        var symbol: String
        var hasRoom: Bool

        var id: String { "\(target)/\(path.map(String.init).joined(separator: "."))" }
    }

    /// One level of the breadcrumb, root first.
    struct Level: Identifiable, Hashable {
        var depth: Int
        var title: String
        var id: Int { depth }
    }

    /// The configuration being edited (`AppModel.shared` in the app).
    let model: AppModel
    /// The user's Apple Shortcuts, for the picker and the library.
    let shortcuts: ShortcutNames
    /// What `RingView` draws on the canvas: the shown level, with an app ring's empty slots
    /// showing the Everywhere actions they inherit.
    let canvas: RingViewModel

    private(set) var target: RingTarget = .global
    /// Ids of the folder slots entered, outermost first.
    private(set) var folderIDs: [Slot.ID] = []
    /// Index path of `folderIDs`, kept valid by `sync()`.
    private(set) var path: [Int] = []
    /// The level shown, as stored: inherited slots are empty here.
    private(set) var ring = Ring()
    private(set) var selectedID: Slot.ID?
    /// Breadcrumb titles, root first.
    private(set) var levels: [Level] = []
    /// False when the shown ring no longer exists (its app ring was removed).
    private(set) var ringExists = true

    /// A slot just filled from a template that still needs details; its editor opens them.
    var pendingSetupID: Slot.ID?
    var focusRequest: FocusRequest?
    var picker: PickerRequest?

    /// The drag-and-drop library beside the canvas.
    var showsLibrary: Bool
    var showsInspector: Bool
    /// The canvas invites a first click until something has been added with the picker.
    private(set) var showsAddHint: Bool

    /// The editor fits the ring to the canvas instead of using the overlay's ring size.
    @ObservationIgnored private var zoom: Double = 1

    static let libraryKey = "RingEditor.showsLibrary"
    static let inspectorKey = "RingEditor.showsInspector"
    private static let addedKey = "RingEditor.hasAddedFromPicker"

    /// Cheap and free of side effects: views create one on every init and keep the first.
    init(target: RingTarget, path: [Int] = [], slot: Int? = nil, model: AppModel = .shared, shortcuts: ShortcutNames = .shared) {
        self.model = model
        self.shortcuts = shortcuts
        canvas = RingViewModel(mode: .editor, ring: Ring(), settings: model.settings)
        canvas.scale = zoom
        let defaults = UserDefaults.standard
        showsLibrary = defaults.object(forKey: Self.libraryKey) as? Bool ?? false
        showsInspector = defaults.object(forKey: Self.inspectorKey) as? Bool ?? true
        showsAddHint = !defaults.bool(forKey: Self.addedKey)
        show(target, path: path, slot: slot)
    }

    // MARK: Reading

    var isNested: Bool { !folderIDs.isEmpty }
    var selectedIndex: Int? { canvas.selected }

    var selectedSlot: Slot? {
        guard let i = selectedIndex, ring.slots.indices.contains(i) else { return nil }
        return ring[i]
    }

    /// The app profile being edited, for app rings.
    var profile: AppProfile? {
        guard case .app(let id) = target else { return nil }
        return model.profile(id)
    }

    /// "Everywhere" for the global ring, the app's name for an app ring.
    var rootTitle: String {
        profile?.appName ?? "Everywhere"
    }

    /// For app rings that inherit: the global ring's slot shown at runtime when slot `index`
    /// is empty (root level only).
    func inheritedSlot(at index: Int) -> Slot? {
        guard !isNested, let profile, profile.inheritsGlobalSlots,
              ring.slots.indices.contains(index), ring[index].isEmpty else { return nil }
        let global = model.config.globalRing
        guard global.slots.indices.contains(index), !global[index].isEmpty else { return nil }
        return global[index]
    }

    /// Spoken/displayed position of a slot: "Top", "Right", "Bottom Left"…
    func direction(of index: Int) -> String {
        let geometry = RingGeometry(slotCount: ring.slotCount)
        let degrees = RingGeometry.normalize(geometry.centerAngle(of: index)) * 180 / .pi
        let names = ["Right", "Bottom Right", "Bottom", "Bottom Left", "Left", "Top Left", "Top", "Top Right"]
        return names[Int((degrees / 45).rounded()) % names.count]
    }

    /// "Slot 3 · Right".
    func position(of index: Int) -> String {
        "Slot \(index + 1) · \(direction(of: index))"
    }

    // MARK: Showing a ring

    /// Starts editing `target`, optionally inside a folder (`path`) with a slot selected.
    func show(_ target: RingTarget, path initialPath: [Int] = [], slot: Int? = nil) {
        self.target = target
        folderIDs = []
        selectedID = nil
        pendingSetupID = nil
        picker = nil
        if var level = model.ring(target) {
            for i in initialPath {
                guard level.slots.indices.contains(i), case .folder(let inner) = level[i].action else { break }
                folderIDs.append(level[i].id)
                level = inner
            }
            if let slot, level.slots.indices.contains(slot) { selectedID = level[slot].id }
            present(level, transition: .none)
        }
        sync()
    }

    /// Re-reads the ring from the model, repairing the folder path and selection if an edit or
    /// undo removed what they pointed at.
    func sync() {
        guard let root = model.ring(target) else {
            ringExists = false
            return
        }
        ringExists = true
        var level = root
        var indices: [Int] = []
        var ids: [Slot.ID] = []
        var crumbs = [Level(depth: 0, title: rootTitle)]
        for id in folderIDs {
            guard let i = level.index(of: id), case .folder(let inner) = level[i].action else { break }
            indices.append(i)
            ids.append(id)
            crumbs.append(Level(depth: crumbs.count, title: level[i].displayTitle))
            level = inner
        }
        if ids != folderIDs {
            folderIDs = ids
            present(level, transition: .none)
        } else {
            if ring != level { ring = level }
            let shown = displayed(level)
            if canvas.ring != shown.ring { canvas.ring = shown.ring }
            if canvas.inheritedSlots != shown.inherited { canvas.inheritedSlots = shown.inherited }
        }
        if path != indices { path = indices }
        if levels != crumbs { levels = crumbs }
        let titles = crumbs.dropFirst().map(\.title)
        if canvas.breadcrumb != titles { canvas.breadcrumb = titles }

        if let id = selectedID, level.index(of: id) == nil { selectedID = nil }
        if let id = picker?.slotID, level.index(of: id) == nil { picker = nil }
        let selection = selectedID.flatMap { level.index(of: $0) }
        if canvas.selected != selection { canvas.selected = selection }
        let valid = level.slots.indices
        if let h = canvas.highlighted, !valid.contains(h) { canvas.highlighted = nil }
        if let d = canvas.dropTarget, !valid.contains(d) { canvas.dropTarget = nil }
        if let d = canvas.dragSource, !valid.contains(d) { canvas.dragSource = nil }

        let badge = indices.isEmpty ? profile.map { RingViewModel.AppBadge(bundleID: $0.bundleID, name: $0.appName) } : nil
        if canvas.appBadge != badge { canvas.appBadge = badge }
    }

    /// Shows `level` (folder ids already set), animating with `transition`.
    private func present(_ level: Ring, transition: RingViewModel.LevelTransition) {
        ring = level
        let shown = displayed(level)
        canvas.showLevel(shown.ring, transition: transition)
        canvas.inheritedSlots = shown.inherited
    }

    /// `level` as drawn: at the root of an app ring that inherits, empty slots show the
    /// Everywhere action at the same position (keeping this ring's slot ids).
    private func displayed(_ level: Ring) -> (ring: Ring, inherited: Set<Int>) {
        guard folderIDs.isEmpty, let profile, profile.inheritsGlobalSlots else { return (level, []) }
        let global = model.config.globalRing
        var shown = level
        var inherited = Set<Int>()
        for i in level.slots.indices where level[i].isEmpty && global.slots.indices.contains(i) && !global[i].isEmpty {
            var slot = global[i]
            slot.id = level[i].id
            shown[i] = slot
            inherited.insert(i)
        }
        return (shown, inherited)
    }

    /// Copies appearance settings into the canvas, keeping the editor's own zoom.
    func applySettings(_ settings: AppSettings) {
        canvas.apply(settings)
        canvas.scale = zoom
    }

    /// Fits the ring into a canvas of `size` points.
    func fit(to size: CGSize) {
        let reference = RingMetrics(theme: canvas.theme, scale: 1, slotCount: ring.slotCount)
        let needed = Double(reference.clampRadius) * 2 + 48
        guard needed > 0, size.width > 0, size.height > 0 else { return }
        let fitted = min(max(Double(min(size.width, size.height)) / needed, 0.45), 1.8)
        guard abs(fitted - zoom) > 0.005 else { return }
        zoom = fitted
        canvas.scale = fitted
    }

    // MARK: Selection and navigation

    func select(_ index: Int?) {
        let id = index.flatMap { ring.slots.indices.contains($0) ? ring[$0].id : nil }
        if pendingSetupID != id { pendingSetupID = nil }
        selectedID = id
        canvas.selected = id.flatMap { ring.index(of: $0) }
    }

    /// Arrow keys: jump toward the direction, then walk around the ring.
    func moveSelection(toward direction: RingGeometry.Direction) {
        select(RingGeometry(slotCount: ring.slotCount).slot(from: selectedIndex, toward: direction))
    }

    /// Tab/⇧Tab. Returns false at the end of the ring so focus can leave the canvas.
    func cycleSelection(forward: Bool) -> Bool {
        let count = ring.slotCount
        if let current = selectedIndex {
            if forward, current == count - 1 { return false }
            if !forward, current == 0 { return false }
        }
        select(RingGeometry(slotCount: count).slot(after: selectedIndex, clockwise: forward))
        return true
    }

    /// Opens the folder at `index`.
    func enterFolder(at index: Int) {
        guard ring.slots.indices.contains(index), case .folder(let inner) = ring[index].action else { return }
        folderIDs.append(ring[index].id)
        selectedID = nil
        canvas.selected = nil
        picker = nil
        present(inner, transition: .push(fromSlot: index))
        sync()
    }

    /// Returns to the enclosing ring, selecting the folder we came out of.
    func goBack() {
        goToLevel(folderIDs.count - 1)
    }

    /// Shows breadcrumb level `depth` (0 is the root ring).
    func goToLevel(_ depth: Int) {
        guard depth >= 0, depth < folderIDs.count else { return }
        let exited = folderIDs[depth]
        let isOneLevel = depth == folderIDs.count - 1
        folderIDs.removeSubrange(depth...)
        picker = nil
        guard let level = model.ring(target, path: Array(path.prefix(depth))) else {
            sync()
            return
        }
        let folderIndex = level.index(of: exited)
        selectedID = folderIndex == nil ? nil : exited
        present(level, transition: isOneLevel ? .pop(toSlot: folderIndex ?? 0) : .none)
        sync()
    }

    func requestFocus(_ request: FocusRequest) {
        if request == .inspector { showsInspector = true }
        focusRequest = request
    }

    /// Selects a slot and moves focus to the inspector to edit it.
    func edit(_ index: Int) {
        select(index)
        requestFocus(.inspector)
    }

    // MARK: Add to Ring picker

    /// The slot the picker is open for, on the shown level.
    var pickerIndex: Int? {
        picker.flatMap { ring.index(of: $0.slotID) }
    }

    /// Selects slot `index` and opens the picker for it.
    func openPicker(at index: Int, from anchor: PickerAnchor) {
        guard ring.slots.indices.contains(index) else { return }
        PendingEdits.commitAll()
        select(index)
        picker = PickerRequest(slotID: ring[index].id, anchor: anchor)
    }

    /// A binding that presents the picker at `anchor`.
    func pickerBinding(for anchor: PickerAnchor) -> Binding<Bool> {
        Binding(
            get: { self.picker?.anchor == anchor },
            set: { isPresented in if !isPresented, self.picker?.anchor == anchor { self.picker = nil } }
        )
    }

    /// Puts the picker's choice in its slot and closes it.
    func choose(_ item: AddableItem) {
        guard let index = pickerIndex else {
            picker = nil
            return
        }
        picker = nil
        add(item, at: index)
    }

    /// Fills slot `index` with `item`. Items that ask for something first (a file, an app not
    /// listed) show their panel, then fill the slot if it is still there.
    func add(_ item: AddableItem, at index: Int) {
        guard ring.slots.indices.contains(index) else { return }
        if let slot = item.slot {
            assign(slot, at: index, needsSetup: item.needsSetup)
            noteAdded()
            return
        }
        let slotID = ring[index].id
        switch item.kind {
        case .chooseFile:
            Task { @MainActor in
                guard let url = await EditorOpenPanel.chooseFileOrFolder(), let i = ring.index(of: slotID) else { return }
                let path = (url.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
                assign(Slot(action: .file(FileTarget(path: path))), at: i)
                noteAdded()
            }
        case .chooseApp:
            Task { @MainActor in
                guard let url = await EditorOpenPanel.chooseApplication(), let i = ring.index(of: slotID) else { return }
                guard let app = AppCatalog.appInfo(at: url) else {
                    Log.app.error("Not an app bundle: \(url.lastPathComponent, privacy: .public)")
                    NSSound.beep()
                    return
                }
                assign(app.editorSlot(), at: i)
                noteAdded()
            }
        default:
            break
        }
    }

    /// The library's double-click: fills the selected slot, or the first empty one.
    func addToSelection(_ item: AddableItem) {
        guard let index = selectedIndex ?? ring.slots.firstIndex(where: \.isEmpty) else {
            NSSound.beep()
            return
        }
        add(item, at: index)
    }

    private func noteAdded() {
        guard showsAddHint else { return }
        showsAddHint = false
        UserDefaults.standard.set(true, forKey: Self.addedKey)
    }

    // MARK: Editing the shown level

    /// Edits the shown level as one undoable step, after writing any text still being typed
    /// (so it lands on the slot it was typed for, not on what replaces it).
    func editRing(_ actionName: String, _ body: (inout Ring) -> Void) {
        PendingEdits.commitAll()
        model.updateRing(target, path: path, actionName, body)
        sync()
    }

    /// Puts `slot`'s content at `index`, keeping the position's identity.
    func assign(_ slot: Slot, at index: Int, needsSetup: Bool = false) {
        guard ring.slots.indices.contains(index) else { return }
        var placed = slot.editorCopy()
        let previous = ring[index]
        placed.id = previous.id
        let name = previous.isEmpty ? "Add \(placed.displayTitle)" : "Replace \(previous.displayTitle) with \(placed.displayTitle)"
        editRing(name) { $0[index] = placed }
        select(index)
        if needsSetup {
            pendingSetupID = placed.id
            requestFocus(.inspector)
        }
    }

    /// Empties a slot, keeping its identity so a selected slot stays selected.
    func clear(at index: Int) {
        guard ring.slots.indices.contains(index), !ring[index].isEmpty else { return }
        let id = ring[index].id
        editRing("Clear \(ring[index].displayTitle)") { $0[index] = Slot(id: id) }
    }

    /// Swaps two slots; the selection follows the slot it was on.
    func swap(_ i: Int, _ j: Int) {
        guard i != j, ring.slots.indices.contains(i), ring.slots.indices.contains(j) else { return }
        let moved = ring[i]
        editRing("Move \(moved.isEmpty ? "Empty Slot" : moved.displayTitle)") { $0.swapAt(i, j) }
    }

    /// Copies slot `source` over slot `destination` (⌥-drag).
    func copy(_ source: Int, onto destination: Int) {
        guard source != destination, ring.slots.indices.contains(source), ring.slots.indices.contains(destination),
              !ring[source].isEmpty else { return }
        var copy = ring[source].editorCopy()
        copy.id = ring[destination].id
        editRing("Copy \(copy.displayTitle)") { $0[destination] = copy }
        select(destination)
    }

    /// The next empty slot clockwise after `index`.
    func nextEmptySlot(after index: Int) -> Int? {
        let count = ring.slotCount
        let ring = ring
        return (1..<count).lazy.map { (index + $0) % count }.first { ring[$0].isEmpty }
    }

    func duplicate(at index: Int) {
        guard ring.slots.indices.contains(index), !ring[index].isEmpty, let free = nextEmptySlot(after: index) else { return }
        var copy = ring[index].editorCopy()
        copy.id = ring[free].id
        editRing("Duplicate \(copy.displayTitle)") { $0[free] = copy }
        select(free)
    }

    /// Turns a slot into a nested ring holding what the slot had (if anything).
    func convertToFolder(at index: Int) {
        guard ring.slots.indices.contains(index), ring[index].action?.isFolder != true else { return }
        let original = ring[index]
        var inner = Ring(slotCount: 6)
        if !original.isEmpty {
            var moved = original.editorCopy()
            moved.id = inner[0].id
            inner[0] = moved
        }
        let name = original.isEmpty ? "Add Nested Ring" : "Convert \(original.displayTitle) to Nested Ring"
        editRing(name) { ring in
            ring[index] = Slot(id: original.id, action: .folder(inner), tint: original.tint)
        }
        select(index)
    }

    func setSlotCount(_ count: Int) {
        guard Ring.slotRange.contains(count), count != ring.slotCount else { return }
        editRing("Change Slot Count to \(count)") { $0.resize(to: count) }
    }

    /// Replaces an app ring's root with a copy of the global ring.
    func copyFromEverywhere() {
        guard case .app(let id) = target, !isNested else { return }
        PendingEdits.commitAll()
        let global = AppModel.freshIDs(model.config.globalRing)
        model.updateProfile(id, "Copy Actions from Everywhere") { $0.ring = global }
        sync()
    }

    // MARK: Moving between rings

    /// Folders in this ring, the enclosing rings, and the other rings' roots.
    func moveDestinations(for index: Int) -> [MoveDestination] {
        var result: [MoveDestination] = []
        for (i, slot) in ring.slots.enumerated() where i != index {
            guard case .folder(let inner) = slot.action else { continue }
            result.append(MoveDestination(target: target, path: path + [i], title: slot.displayTitle,
                                          symbol: "circle.grid.cross", hasRoom: inner.filledCount < inner.slotCount))
        }
        for depth in stride(from: path.count - 1, through: 0, by: -1) {
            let enclosing = Array(path.prefix(depth))
            guard let level = model.ring(target, path: enclosing) else { continue }
            result.append(MoveDestination(target: target, path: enclosing, title: levels[depth].title,
                                          symbol: depth == 0 ? "circle.circle" : "arrow.turn.left.up",
                                          hasRoom: level.filledCount < level.slotCount))
        }
        let config = model.config
        if target != .global {
            result.append(MoveDestination(target: .global, path: [], title: "Everywhere", symbol: "globe",
                                          hasRoom: config.globalRing.filledCount < config.globalRing.slotCount))
        }
        for profile in config.appProfiles where target != .app(profile.id) {
            result.append(MoveDestination(target: .app(profile.id), path: [], title: profile.appName, symbol: "app",
                                          hasRoom: profile.ring.filledCount < profile.ring.slotCount))
        }
        return result
    }

    /// Moves slot `index` into the first empty slot of `destination`, as one undoable step.
    func move(_ index: Int, to destination: MoveDestination) {
        guard ring.slots.indices.contains(index), !ring[index].isEmpty else { return }
        PendingEdits.commitAll()
        let source = ring[index]
        let sourceTarget = target
        let sourcePath = path
        model.update("Move \(source.displayTitle) to \(destination.title)") { config in
            guard let level = config.editorRing(destination.target, path: destination.path),
                  let free = level.slots.firstIndex(where: \.isEmpty) else { return }
            var moved = source.editorCopy()
            moved.id = level[free].id
            config.editorUpdateRing(destination.target, path: destination.path) { $0[free] = moved }
            config.editorUpdateRing(sourceTarget, path: sourcePath) { $0[index] = Slot(id: source.id) }
        }
        sync()
    }

    // MARK: Editing one slot

    /// A stable reference to a slot of the shown level, for the inspector's bindings.
    func handle(for id: Slot.ID) -> SlotHandle {
        SlotHandle(model: model, target: target, path: path, slotID: id)
    }
}

/// Reads and edits one slot by id at a fixed ring and folder path, so edits committed late (when
/// a text field loses focus after the selection moved on) still reach the right slot.
struct SlotHandle {
    let model: AppModel
    let target: RingTarget
    let path: [Int]
    let slotID: Slot.ID

    var slot: Slot? {
        guard let ring = model.ring(target, path: path), let i = ring.index(of: slotID) else { return nil }
        return ring[i]
    }

    /// Applies `body` to the slot as one undoable step.
    func update(_ actionName: String, _ body: (inout Slot) -> Void) {
        model.updateRing(target, path: path, actionName) { ring in
            guard let i = ring.index(of: slotID) else { return }
            body(&ring[i])
        }
    }

    /// A binding to part of the slot; every write is one undoable step named `actionName`.
    func binding<Value>(_ keyPath: WritableKeyPath<Slot, Value>, default fallback: Value, actionName: String) -> Binding<Value> {
        Binding(
            get: { slot?[keyPath: keyPath] ?? fallback },
            set: { newValue in update(actionName) { $0[keyPath: keyPath] = newValue } }
        )
    }

    /// A binding to the slot's action (empty slots read as `fallback`). Writes apply only while
    /// the slot still holds an action of the same kind: a draft committed late (a text field
    /// losing focus as the slot is cleared or replaced) never brings the old action back.
    func actionBinding(default fallback: Action, actionName: @escaping (Action) -> String) -> Binding<Action> {
        Binding(
            get: { slot?.action ?? fallback },
            set: { newValue in
                update(actionName(newValue)) { slot in
                    guard slot.action?.kind == newValue.kind else { return }
                    slot.action = newValue
                }
            }
        )
    }
}

extension Slot {
    /// A copy with fresh ids (recursively for nested rings), for duplicates and moves.
    func editorCopy() -> Slot {
        var copy = self
        copy.id = UUID()
        if case .folder(let inner) = action { copy.action = .folder(AppModel.freshIDs(inner)) }
        return copy
    }
}

extension Ring {
    /// Actions dropped by resizing this ring to `count` slots.
    func editorActionsLost(resizingTo count: Int) -> Int {
        max(0, filledCount - count)
    }
}

private extension HaloConfig {
    func editorRing(_ target: RingTarget, path: [Int]) -> Ring? {
        switch target {
        case .global:
            return globalRing.ring(at: path)
        case .app(let id):
            guard let i = profileIndex(id: id) else { return nil }
            return appProfiles[i].ring.ring(at: path)
        }
    }

    mutating func editorUpdateRing(_ target: RingTarget, path: [Int], _ body: (inout Ring) -> Void) {
        switch target {
        case .global:
            globalRing.updateRing(at: path, body)
        case .app(let id):
            guard let i = profileIndex(id: id) else { return }
            appProfiles[i].ring.updateRing(at: path, body)
        }
    }
}
