import AppKit
import HaloCore
import SwiftUI

/// The Add to Ring picker: one search over apps and every kind of action, in labelled sections
/// (apps first, as large icons). One click, or Return on the highlighted item, fills the slot.
///
/// Keyboard: type to search; ↑↓←→ and Tab move the highlight (↑↓ also from the search field);
/// Return or Space chooses; Esc closes.
struct AddToRingPicker: View {
    static let size = CGSize(width: 480, height: 560)

    let title: String
    let subtitle: String
    let recentApps: [AppInfo]
    let shortcuts: ShortcutNames
    /// The app ring's app, whose own actions are listed first.
    let ringApp: AppInfo?
    let onChoose: (AddableItem) -> Void
    let onCancel: () -> Void

    @ViewState private var query: String
    /// The keyboard highlight; nil means "the first result while searching".
    @ViewState private var highlighted: String?
    @ViewState private var expanded: Set<AddableGroup> = []
    @ViewState private var webAddress = ""
    @FocusState private var focus: PickerField?

    init(title: String, subtitle: String, recentApps: [AppInfo], shortcuts: ShortcutNames = .shared, ringApp: AppInfo? = nil, query: String = "",
         onChoose: @escaping (AddableItem) -> Void, onCancel: @escaping () -> Void) {
        self.ringApp = ringApp
        self.title = title
        self.subtitle = subtitle
        self.recentApps = recentApps
        self.shortcuts = shortcuts
        self.onChoose = onChoose
        self.onCancel = onCancel
        self._query = ViewState(initialValue: query)
    }

    var body: some View {
        let catalog = AddableCatalog(purpose: .picker, recentApps: recentApps, shortcutNames: shortcuts.names, ringApp: ringApp)
        let sections = catalog.sections(matching: query, expanded: expanded)
        let navigation = GridNavigation(sections: sections.map { .init(ids: $0.items.map(\.id), columns: $0.group.pickerColumns) })
        let current = highlighted ?? (query.isEmpty ? nil : navigation.first)
        let keys = PickerKeys(sections: sections, navigation: navigation, current: current)

        VStack(spacing: 0) {
            header
            searchField(keys)
            Divider()
            if sections.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(maxHeight: .infinity)
            } else {
                results(sections, keys: keys)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .defaultFocus($focus, .search)
        .onAppear {
            if AppCatalog.shared.installed.isEmpty { AppCatalog.shared.refresh() }
            shortcuts.loadIfNeeded()
            Task { @MainActor in focus = .search }
        }
        .onChange(of: query) { highlighted = nil }
        .onExitCommand(perform: onCancel)
    }

    // MARK: Header and search

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 12)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private func searchField(_ keys: PickerKeys) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search apps and actions", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($focus, equals: .search)
                .onSubmit { chooseCurrent(keys) }
                .onKeyPress(.downArrow) { move(.down, keys) }
                .onKeyPress(.upArrow) { move(.up, keys) }
                .accessibilityLabel("Search apps and actions")
                .accessibilityHint("Press Return to add the highlighted result, or the arrow keys to move between results.")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    // MARK: Results

    private func results(_ sections: [AddableSection], keys: PickerKeys) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            sectionHeader(section)
                            sectionBody(section, current: keys.current)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.automatic)
            .accessibilityLabel("Results")
            .focusable()
            .focused($focus, equals: .results)
            .focusEffectDisabled()
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                switch press.key {
                case .upArrow: move(.up, keys)
                case .downArrow: move(.down, keys)
                case .leftArrow: move(.left, keys)
                default: move(.right, keys)
                }
            }
            .onKeyPress(keys: [.tab, KeyEquivalent("\u{19}")], phases: .down) { press in
                let backward = press.key != .tab || press.modifiers.contains(.shift)
                if backward, keys.current == keys.navigation.first {
                    focus = .search
                    return .handled
                }
                return move(backward ? .left : .right, keys)
            }
            .onKeyPress(keys: [.return, .space]) { _ in
                chooseCurrent(keys)
                return .handled
            }
            .onKeyPress(.delete) {
                if !query.isEmpty { query.removeLast() }
                focus = .search
                return .handled
            }
            .onKeyPress(characters: .alphanumerics.union(.punctuationCharacters), phases: .down) { press in
                guard press.modifiers.subtracting(.shift).isEmpty else { return .ignored }
                query += press.characters
                focus = .search
                return .handled
            }
            .onChange(of: focus) { previous, field in
                // Tabbing in from the search field shows where the arrow keys start.
                if previous == .search, field == .results, highlighted == nil { highlighted = keys.current ?? keys.navigation.first }
            }
            .onChange(of: keys.current) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    private func sectionHeader(_ section: AddableSection) -> some View {
        let group = section.group
        let isExpanded = expanded.contains(group)
        let isLoading = (group == .apps && AppCatalog.shared.isScanning) || (group == .shortcuts && shortcuts.isLoading)
        return HStack(spacing: 6) {
            Text(section.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            if isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel("Loading")
            }
            Spacer(minLength: 8)
            if query.isEmpty, section.hiddenCount > 0 || isExpanded {
                let total = section.items.filter { $0.kind != .chooseApp }.count + section.hiddenCount
                Button(isExpanded ? "Show Less" : "Show All \(total)") {
                    if isExpanded { expanded.remove(group) } else { expanded.insert(group) }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tint)
                .font(.caption)
                .accessibilityLabel(isExpanded ? "Show fewer \(group.title.lowercased())" : "Show all \(group.title.lowercased())")
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func sectionBody(_ section: AddableSection, current: String?) -> some View {
        switch section.group {
        case .apps, .installedApps:
            TileRows(items: section.items, columns: section.group.pickerColumns, spacing: 2) { item in
                IconTile(title: item.title, help: item.subtitle, isHighlighted: item.id == current, action: { choose(item) }) {
                    AppTileIcon(item: item)
                }
                .id(item.id)
            }
        case .websites:
            VStack(spacing: 6) {
                ForEach(section.items) { item in
                    if item.kind == .webEntry {
                        WebAddressRow(address: $webAddress, isHighlighted: item.id == current, focus: $focus) { address in
                            onChoose(.website(address))
                        }
                        .id(item.id)
                    } else {
                        tile(item, current: current)
                    }
                }
            }
        default:
            TileRows(items: section.items, columns: section.group.pickerColumns, spacing: 6) { item in
                tile(item, current: current)
            }
        }
    }

    private func tile(_ item: AddableItem, current: String?) -> some View {
        ActionTile(title: item.title, subtitle: item.subtitle, icon: item.icon, isHighlighted: item.id == current) {
            choose(item)
        }
        .id(item.id)
    }

    // MARK: Choosing and moving

    private func choose(_ item: AddableItem) {
        if item.kind == .webEntry {
            focus = .web
            return
        }
        onChoose(item)
    }

    private func chooseCurrent(_ keys: PickerKeys) {
        guard let id = keys.current, let item = keys.sections.lazy.flatMap(\.items).first(where: { $0.id == id }) else { return }
        choose(item)
    }

    private func move(_ move: GridNavigation.Move, _ keys: PickerKeys) -> KeyPress.Result {
        guard let target = keys.navigation.target(from: keys.current, move) else { return .ignored }
        highlighted = target
        return .handled
    }
}

/// Where keyboard focus is inside the picker.
private enum PickerField: Hashable {
    case search, results, web
}

/// What the key handlers need from one render of the picker.
private struct PickerKeys {
    var sections: [AddableSection]
    var navigation: GridNavigation
    var current: String?
}

/// An app's icon, or the dashed "+" of "Other App…".
private struct AppTileIcon: View {
    let item: AddableItem

    var body: some View {
        switch item.kind {
        case .app(let app):
            Image(nsImage: AppCatalog.shared.icon(forPath: app.url.path(percentEncoded: false)))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .accessibilityHidden(true)
        default:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .padding(3)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .accessibilityHidden(true)
        }
    }
}

/// The Websites section's "type an address" row.
private struct WebAddressRow: View {
    @Binding var address: String
    let isHighlighted: Bool
    let focus: FocusState<PickerField?>.Binding
    let onAdd: (String) -> Void

    var body: some View {
        let normalized = WebAddress.normalized(address)
        HStack(spacing: 9) {
            SlotIconTile(icon: .symbol(name: "globe"), size: 30)
            TextField("Type a web address, like apple.com", text: $address)
                .textFieldStyle(.roundedBorder)
                .focused(focus, equals: .web)
                .onSubmit { add(normalized) }
                .accessibilityLabel("Web address")
            Button("Add") { add(normalized) }
                .disabled(normalized == nil)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(TileBackground(isHighlighted: isHighlighted, isHovered: false, resting: true))
    }

    private func add(_ normalized: String?) {
        guard let normalized else {
            NSSound.beep()
            return
        }
        onAdd(normalized)
    }
}

/// The picker as the editor shows it, for the slot `session.picker` is open for.
struct RingPickerPopover: View {
    let session: RingEditorSession

    var body: some View {
        let index = session.pickerIndex
        let slot = index.map { session.ring[$0] }
        AddToRingPicker(
            title: slot.map { $0.isEmpty ? "Add to Ring" : "Replace “\($0.displayTitle)”" } ?? "Add to Ring",
            subtitle: index.map(subtitle) ?? "",
            recentApps: session.model.recentApps,
            shortcuts: session.shortcuts,
            ringApp: session.profile.flatMap { AppCatalog.shared.info(bundleID: $0.bundleID) },
            onChoose: session.choose,
            onCancel: { session.picker = nil }
        )
    }

    private func subtitle(_ index: Int) -> String {
        if let inherited = session.inheritedSlot(at: index) {
            return "\(session.position(of: index)) · now “\(inherited.displayTitle)” from Everywhere"
        }
        return session.position(of: index)
    }
}
