import HaloCore
import SwiftUI

/// The drag-and-drop library beside the canvas, for arranging many slots quickly: the same
/// groups as the Add to Ring picker, as labelled sections that fold open (Apps open first).
/// Rows drag onto the ring; double-click or Return adds to the selected slot (or the first
/// empty one).
struct ActionLibraryView: View {
    let session: RingEditorSession

    @ViewState private var query = ""
    @ViewState private var selection: String?
    @ViewState private var expanded: Set<AddableGroup> = [.apps]
    @FocusState private var searchFocused: Bool
    @FocusState private var listFocused: Bool

    var body: some View {
        let shortcuts = session.shortcuts
        let catalog = AddableCatalog(purpose: .library, recentApps: session.model.recentApps, shortcutNames: shortcuts.names,
                                     ringApp: session.profile.flatMap { AppCatalog.shared.info(bundleID: $0.bundleID) })
        let sections = catalog.sections(matching: query)
        VStack(spacing: 0) {
            searchField(sections)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 8)

            if sections.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(maxHeight: .infinity)
            } else {
                list(sections)
            }

            Divider()
            Text("Drag onto a slot, or double-click to add.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
        }
        .background(.background.secondary)
        .onAppear {
            if AppCatalog.shared.installed.isEmpty { AppCatalog.shared.refresh() }
            shortcuts.loadIfNeeded()
        }
    }

    // MARK: Search

    private func searchField(_ sections: [AddableSection]) -> some View {
        let first = sections.first?.items.first
        return PickerSearchField(prompt: "Search Library", text: $query, isFocused: $searchFocused)
            .onSubmit {
                if let first { session.addToSelection(first) }
            }
            .onKeyPress(.downArrow) {
                guard let first else { return .ignored }
                selection = first.id
                listFocused = true
                return .handled
            }
            .accessibilityHint("Press Return to add the first result to the selected slot")
    }

    // MARK: List

    private func list(_ sections: [AddableSection]) -> some View {
        let byID = Dictionary(sections.flatMap { $0.items.map { ($0.id, $0) } }, uniquingKeysWith: { first, _ in first })
        return List(selection: $selection) {
            ForEach(sections) { section in
                DisclosureGroup(isExpanded: expansion(section.group)) {
                    ForEach(section.items) { item in
                        LibraryRow(item: item)
                            .tag(item.id)
                    }
                } label: {
                    LibraryGroupLabel(section: section)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .focused($listFocused)
        .contextMenu(forSelectionType: String.self) { ids in
            if let item = ids.first.flatMap({ byID[$0] }) {
                contextMenu(for: item)
            }
        } primaryAction: { ids in
            if let item = ids.first.flatMap({ byID[$0] }) { session.addToSelection(item) }
        }
    }

    /// Searching opens every section with results; otherwise sections remember their state.
    private func expansion(_ group: AddableGroup) -> Binding<Bool> {
        Binding(
            get: { !query.isEmpty || expanded.contains(group) },
            set: { open in
                if open { expanded.insert(group) } else { expanded.remove(group) }
            }
        )
    }

    @ViewBuilder
    private func contextMenu(for item: AddableItem) -> some View {
        Button(session.selectedIndex == nil ? "Add to Next Empty Slot" : "Add to Selected Slot", systemImage: "plus.circle") {
            session.addToSelection(item)
        }
        Menu("Add to Slot", systemImage: "circle.grid.cross") {
            ForEach(Array(session.ring.slots.enumerated()), id: \.element.id) { index, slot in
                Button("\(index + 1). \(slot.isEmpty ? "Empty" : slot.displayTitle)") {
                    session.add(item, at: index)
                }
            }
        }
    }
}

/// A category: its name and symbol, and how many items it holds.
private struct LibraryGroupLabel: View {
    let section: AddableSection

    var body: some View {
        HStack(spacing: 6) {
            Label(section.title, systemImage: section.group.symbol)
            Spacer(minLength: 4)
            Text("\(section.items.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(section.items.count) items")
        }
        .accessibilityElement(children: .combine)
    }
}

/// One library row: icon, title and subtitle. Draggable onto the ring.
private struct LibraryRow: View {
    let item: AddableItem

    var body: some View {
        HStack(spacing: 9) {
            SlotIconTile(icon: item.icon, size: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .modifier(LibraryDrag(item: item))
        .help(item.subtitle)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double-click to add it to the selected slot, or drag it onto the ring.")
    }
}

/// Makes a row draggable when its item can be dropped on the ring.
private struct LibraryDrag: ViewModifier {
    let item: AddableItem

    func body(content: Content) -> some View {
        if let token = item.dragToken {
            content.draggable(token) {
                LibraryDragPreview(item: item)
            }
        } else {
            content
        }
    }
}

/// The floating capsule shown while dragging a library item.
private struct LibraryDragPreview: View {
    let item: AddableItem

    var body: some View {
        HStack(spacing: 8) {
            SlotIconTile(icon: item.icon, size: 24)
            Text(item.title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }
}
