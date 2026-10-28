import AppKit
import Combine
import HaloCore
import SwiftUI

/// The editor for one ring (global or app-specific): the interactive ring canvas, the slot
/// inspector, and the drag-and-drop action library (hidden until shown from the toolbar; the
/// Add to Ring picker covers the common case).
struct RingEditorView: View {
    let target: RingTarget
    let initialPath: [Int]
    let initialSlot: Int?

    @ViewState private var session: RingEditorSession
    @ViewState private var pendingSlotCount: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - initialPath: folder slot indices to open, outermost first.
    ///   - initialSlot: slot to select at that level.
    ///   - model: the configuration to edit.
    init(target: RingTarget, initialPath: [Int] = [], initialSlot: Int? = nil, model: AppModel = .shared) {
        self.target = target
        self.initialPath = initialPath
        self.initialSlot = initialSlot
        self._session = ViewState(initialValue: RingEditorSession(target: target, path: initialPath, slot: initialSlot, model: model))
    }

    /// Edits an existing session (snapshots set one up in a particular state).
    init(session: RingEditorSession) {
        self.target = session.target
        self.initialPath = session.path
        self.initialSlot = session.selectedIndex
        self._session = ViewState(initialValue: session)
    }

    var body: some View {
        let model = session.model
        content
            .toolbar { toolbar }
            .inspector(isPresented: inspectorBinding) {
                SlotInspector(session: session)
                    .inspectorColumnWidth(min: 280, ideal: 330, max: 460)
            }
            .onChange(of: Destination(target: target, path: initialPath, slot: initialSlot)) { _, destination in
                session.show(destination.target, path: destination.path, slot: destination.slot)
            }
            .onChange(of: model.config) { session.sync() }
            .onChange(of: model.settings) { _, settings in
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { session.applySettings(settings) }
            }
            .modifier(SlotCountConfirmation(pendingCount: $pendingSlotCount, filledCount: session.ring.filledCount) { count in
                session.setSlotCount(count)
            })
    }

    private struct Destination: Hashable {
        var target: RingTarget
        var path: [Int]
        var slot: Int?
    }

    @ViewBuilder
    private var content: some View {
        if session.ringExists {
            HStack(spacing: 0) {
                if session.showsLibrary {
                    ActionLibraryView(session: session)
                        .frame(width: 272)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    Divider()
                }
                VStack(spacing: 0) {
                    EditorBreadcrumbBar(session: session)
                    RingEditorCanvas(session: session)
                    CanvasFooter(session: session)
                }
                .frame(minWidth: 260)
                .background(CanvasBackdrop(accent: session.canvas.accent.color, ringRadius: session.canvas.metrics.outerRadius))
            }
        } else {
            ContentUnavailableView {
                Label("Ring Not Found", systemImage: "circle.slash")
            } description: {
                Text("This app ring was removed.")
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Toggle(isOn: Binding(get: { session.showsLibrary }, set: setLibraryVisible)) {
                Label("Action Library", systemImage: "books.vertical")
            }
            .help(session.showsLibrary ? "Hide the action library" : "Show the action library, to drag actions onto the ring")
        }

        ToolbarItem(placement: .primaryAction) {
            EditorUndoButtons(manager: session.model.undoManager)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Picker("Slots", selection: Binding(get: { session.ring.slotCount }, set: requestSlotCount)) {
                ForEach(Array(Ring.slotRange), id: \.self) { count in
                    Text("\(count) Slots").tag(count)
                }
            }
            .pickerStyle(.menu)
            .help("Number of slots in this ring")

            Picker("Theme", selection: themeBinding) {
                Text("Classic").tag(RingTheme.classic)
                Text("Glass").tag(RingTheme.glass)
            }
            .pickerStyle(.segmented)
            .help("Ring style, for every ring")
        }

        if let profile = session.profile {
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: profileBinding(profile.id, \.isEnabled, on: "Turn On \(profile.appName) Ring", off: "Turn Off \(profile.appName) Ring")) {
                    Text("Enabled")
                }
                .toggleStyle(.switch)
                .help("Use this ring while \(profile.appName) is in front")

                Toggle(isOn: profileBinding(profile.id, \.inheritsGlobalSlots, on: "Fill Empty Slots from Everywhere", off: "Stop Filling from Everywhere")) {
                    Label("Fill from Everywhere", systemImage: "circle.dotted.circle")
                }
                .help("Fill empty slots with the actions from Everywhere")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                OverlayController.shared.presentForTesting(target: target)
            } label: {
                Label("Try It", systemImage: "play.circle")
            }
            .help("Open this ring in the middle of the screen")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                inspectorBinding.wrappedValue.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.trailing")
            }
            .help(session.showsInspector ? "Hide the inspector" : "Show the inspector")
        }
    }

    private var inspectorBinding: Binding<Bool> {
        let session = session
        return Binding(
            get: { session.showsInspector },
            set: { shown in
                session.showsInspector = shown
                UserDefaults.standard.set(shown, forKey: RingEditorSession.inspectorKey)
            }
        )
    }

    private func setLibraryVisible(_ visible: Bool) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { session.showsLibrary = visible }
        UserDefaults.standard.set(visible, forKey: RingEditorSession.libraryKey)
    }

    private func requestSlotCount(_ count: Int) {
        if session.ring.editorActionsLost(resizingTo: count) > 0 {
            pendingSlotCount = count
        } else {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { session.setSlotCount(count) }
        }
    }

    private var themeBinding: Binding<RingTheme> {
        let model = session.model
        return Binding(
            get: { model.settings.theme },
            set: { theme in model.updateSettings("Change Theme") { $0.theme = theme } }
        )
    }

    private func profileBinding(_ id: AppProfile.ID, _ keyPath: WritableKeyPath<AppProfile, Bool>, on: String, off: String) -> Binding<Bool> {
        let model = session.model
        return Binding(
            get: { model.profile(id)?[keyPath: keyPath] ?? false },
            set: { value in model.updateProfile(id, value ? on : off) { $0[keyPath: keyPath] = value } }
        )
    }
}

/// Asks before a smaller slot count drops actions (toolbar and nested-ring inspector alike).
struct SlotCountConfirmation: ViewModifier {
    @Binding var pendingCount: Int?
    let filledCount: Int
    let onConfirm: (Int) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Remove Actions?",
            isPresented: Binding(get: { pendingCount != nil }, set: { if !$0 { pendingCount = nil } }),
            presenting: pendingCount
        ) { count in
            Button("Change to \(count) Slots", role: .destructive) { onConfirm(count) }
            Button("Cancel", role: .cancel) {}
        } message: { count in
            let lost = max(0, filledCount - count)
            Text("\(count) slots can't hold all \(filledCount) actions, so \(lost == 1 ? "1 action is" : "\(lost) actions are") removed from the end. You can undo this.")
        }
    }
}

// MARK: - Breadcrumb

/// "Everywhere › Windows" above the canvas, with Back (⌘[).
private struct EditorBreadcrumbBar: View {
    let session: RingEditorSession

    var body: some View {
        HStack(spacing: 6) {
            if session.isNested {
                Button {
                    session.goBack()
                } label: {
                    Image(systemName: "chevron.backward")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("[", modifiers: .command)
                .help("Back to the enclosing ring")
                .accessibilityLabel("Back")
            }

            ForEach(session.levels) { level in
                if level.depth > 0 {
                    Image(systemName: "chevron.compact.right")
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                if level.depth == session.levels.count - 1 {
                    crumb(level)
                        .fontWeight(.semibold)
                        .accessibilityAddTraits(.isHeader)
                } else {
                    Button {
                        session.goToLevel(level.depth)
                    } label: {
                        crumb(level)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Go to \(level.title)")
                }
            }

            Spacer(minLength: 8)

            Text("\(session.ring.filledCount) of \(session.ring.slotCount) slots used")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ring path")
    }

    private func crumb(_ level: RingEditorSession.Level) -> some View {
        HStack(spacing: 5) {
            if level.depth == 0 {
                if let profile = session.profile {
                    Image(nsImage: AppCatalog.shared.icon(forBundleID: profile.bundleID))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 16, height: 16)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "globe")
                        .accessibilityHidden(true)
                }
            } else {
                Image(systemName: "circle.grid.cross")
                    .accessibilityHidden(true)
            }
            Text(level.title)
                .lineLimit(1)
        }
    }
}

// MARK: - Footer

/// Under the canvas: an empty-ring prompt, the first-run hint, or a short tip.
private struct CanvasFooter: View {
    let session: RingEditorSession

    var body: some View {
        Group {
            if session.ring.isEmpty, session.ring.slots.indices.allSatisfy({ session.inheritedSlot(at: $0) == nil }) {
                VStack(spacing: 10) {
                    Text(session.isNested ? "This nested ring is empty" : "This ring is empty")
                        .font(.headline)
                    hint
                    if session.profile != nil, !session.isNested {
                        Button("Copy Actions from Everywhere", systemImage: "doc.on.doc") { session.copyFromEverywhere() }
                            .controlSize(.small)
                    }
                }
                .padding(.bottom, 18)
            } else if session.showsAddHint, !hasInherited, session.ring.filledCount < session.ring.slotCount {
                hint
                    .padding(.bottom, 16)
            } else {
                Text(tip)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }

    /// The friendly first-run invitation.
    private var hint: some View {
        Label {
            Text("Click a slot to add an app or action")
        } icon: {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.tint)
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.background, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    private var hasInherited: Bool {
        !session.canvas.inheritedSlots.isEmpty
    }

    private var tip: String {
        if hasInherited {
            return "Faded slots show the Everywhere action. Click one to give \(session.rootTitle) its own."
        }
        return "Click a slot to change it. Drag one slot onto another to swap them, or hold ⌥ to copy."
    }
}

// MARK: - Undo

/// Undo and Redo buttons for ring edits. They go through the responder chain like Edit › Undo
/// (⌘Z / ⇧⌘Z): the settings window's undo manager is the model's, so the buttons, the menu and
/// the keys always agree. (Text editors keep their typing on their own undo stacks.)
private struct EditorUndoButtons: View {
    let manager: UndoManager
    @ViewState private var state = UndoState()

    private struct UndoState: Equatable {
        var canUndo = false
        var canRedo = false
        var undoTitle = "Undo"
        var redoTitle = "Redo"

        init() {}

        init(_ manager: UndoManager) {
            canUndo = manager.canUndo
            canRedo = manager.canRedo
            undoTitle = manager.undoMenuItemTitle
            redoTitle = manager.redoMenuItemTitle
        }
    }

    var body: some View {
        ControlGroup {
            Button {
                perform(undo: true)
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!state.canUndo)
            .help(state.undoTitle)

            Button {
                perform(undo: false)
            } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .disabled(!state.canRedo)
            .help(state.redoTitle)
        }
        .onAppear { state = UndoState(manager) }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidCloseUndoGroup, object: manager)) { _ in
            state = UndoState(manager)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange, object: manager)) { _ in
            state = UndoState(manager)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidRedoChange, object: manager)) { _ in
            state = UndoState(manager)
        }
    }

    private func perform(undo: Bool) {
        // `undo:`/`redo:` are implemented by NSWindow and text views, not declared in Swift.
        if NSApp.sendAction(undo ? Selector(("undo:")) : Selector(("redo:")), to: nil, from: nil) { return }
        if undo, manager.canUndo { manager.undo() }
        if !undo, manager.canRedo { manager.redo() }
    }
}
