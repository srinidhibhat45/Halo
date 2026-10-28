import AppKit
import HaloCore
import SwiftUI
import UniformTypeIdentifiers

/// Creates an app ring: explains what one is, then one click on an app creates its ring and
/// shows it. Suggestions (recent, then running apps) come first, then every installed app, all
/// searchable, or any app chosen from disk. Apps that already have a ring are badged, and
/// choosing one shows its ring instead of adding another.
struct AddAppRingSheet: View {
    /// Called with the ring to show: the new one, or the app's existing ring.
    let onChoose: (AppProfile.ID) -> Void
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @ViewState private var query: String
    /// The keyboard highlight (an `AppGroup.rowID`); nil means "the first result while searching".
    @ViewState private var highlighted: String?
    @ViewState private var startsWithCopy = false
    @ViewState private var alert: PaneAlert?
    @FocusState private var focus: SheetField?

    static let size = CGSize(width: 600, height: 620)
    private static let columns = 7

    init(model: AppModel = .shared, query: String = "", onChoose: @escaping (AppProfile.ID) -> Void) {
        self.model = model
        self.onChoose = onChoose
        self._query = ViewState(initialValue: query)
    }

    var body: some View {
        let groups = self.groups
        let navigation = GridNavigation(sections: groups.map { group in .init(ids: group.apps.map(group.rowID), columns: Self.columns) })
        let current = highlighted ?? (query.isEmpty ? nil : navigation.first)
        VStack(spacing: 0) {
            header
            searchField(navigation: navigation, current: current, groups: groups)
            Divider()
            if groups.isEmpty {
                if AppCatalog.shared.isScanning {
                    ProgressView("Finding Apps…")
                        .frame(maxHeight: .infinity)
                } else {
                    ContentUnavailableView.search(text: query)
                        .frame(maxHeight: .infinity)
                }
            } else {
                appGrid(groups, navigation: navigation, current: current)
            }
            Divider()
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .defaultFocus($focus, .search)
        .onAppear {
            if AppCatalog.shared.installed.isEmpty { AppCatalog.shared.refresh() }
            Task { @MainActor in focus = .search }
        }
        .onChange(of: query) { highlighted = nil }
        .alert(alert?.title ?? "", isPresented: Binding(isPresenting: $alert), presenting: alert) { _ in
            Button("OK") {}
        } message: { alert in
            Text(alert.message)
        }
    }

    // MARK: Header and search

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            AppRingGlyph()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("Add App Ring")
                    .font(.title2.bold())
                Text("An app ring replaces Everywhere while its app is in front, so each app can have its own actions.")
                    .fixedSize(horizontal: false, vertical: true)
                Text("Click an app to create its ring.")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 16)
    }

    private func searchField(navigation: GridNavigation, current: String?, groups: [AppGroup]) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search Apps", text: $query, prompt: Text("Search apps"))
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($focus, equals: .search)
                .onSubmit { chooseCurrent(current, in: groups) }
                .onKeyPress(.downArrow) { move(.down, from: current, navigation) }
                .onKeyPress(.upArrow) { move(.up, from: current, navigation) }
                .accessibilityLabel("Search apps")
                .accessibilityHint("Press Return to create a ring for the highlighted app.")
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
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    // MARK: Apps

    private func appGrid(_ groups: [AppGroup], navigation: GridNavigation, current: String?) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Text(group.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .accessibilityAddTraits(.isHeader)
                                if group.kind == .installed, AppCatalog.shared.isScanning {
                                    ProgressView()
                                        .controlSize(.mini)
                                        .accessibilityLabel("Finding apps")
                                }
                            }
                            .padding(.horizontal, 4)
                            TileRows(items: group.apps, columns: Self.columns, spacing: 2) { app in
                                let existing = hasRing(app)
                                IconTile(title: app.name,
                                         help: existing ? "Show the \(app.name) ring" : "Create a ring for \(app.name)",
                                         isHighlighted: group.rowID(app) == current,
                                         badge: existing ? "has a ring" : nil,
                                         action: { choose(app) }) {
                                    Image(nsImage: AppCatalog.shared.icon(forPath: app.url.path(percentEncoded: false)))
                                        .resizable()
                                        .interpolation(.high)
                                        .aspectRatio(contentMode: .fit)
                                        .accessibilityHidden(true)
                                }
                                .id(group.rowID(app))
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .focusable()
            .focused($focus, equals: .grid)
            .focusEffectDisabled()
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                let move: GridNavigation.Move = switch press.key {
                case .upArrow: .up
                case .downArrow: .down
                case .leftArrow: .left
                default: .right
                }
                return self.move(move, from: current, navigation)
            }
            .onKeyPress(keys: [.return, .space]) { _ in
                chooseCurrent(current, in: groups)
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
                if previous == .search, field == .grid, highlighted == nil { highlighted = current ?? navigation.first }
            }
            .onChange(of: current) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Toggle("Start with a copy of the Everywhere actions", isOn: $startsWithCopy)
                    .toggleStyle(.checkbox)
                Text(startsWithCopy
                     ? "You can change them without affecting Everywhere."
                     : "Otherwise its empty slots show the Everywhere actions until you fill them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
            }
            Spacer(minLength: 8)
            Button("Other App…", action: chooseFromDisk)
                .help("Choose an app that isn't listed")
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: Data

    /// Suggestions and all apps, or search results while searching.
    private var groups: [AppGroup] {
        let me = Bundle.main.bundleIdentifier
        let catalog = AppCatalog.shared
        var seen = Set<String>()
        let suggested = (model.recentApps + catalog.runningApps).filter { $0.bundleID != me && seen.insert($0.bundleID).inserted }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.isEmpty else {
            var unique = Set<String>()
            let matches = (suggested + catalog.installed)
                .filter { $0.bundleID != me && unique.insert($0.bundleID).inserted }
                .filter { $0.name.localizedStandardContains(trimmed) || $0.bundleID.localizedStandardContains(trimmed) }
                .sorted { lhs, rhs in
                    let l = lhs.name.range(of: trimmed, options: [.caseInsensitive, .anchored]) != nil
                    let r = rhs.name.range(of: trimmed, options: [.caseInsensitive, .anchored]) != nil
                    return l != r ? l : lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
            return matches.isEmpty ? [] : [AppGroup(kind: .results, apps: matches)]
        }

        var groups: [AppGroup] = []
        if !suggested.isEmpty { groups.append(AppGroup(kind: .suggested, apps: Array(suggested.prefix(Self.columns * 2)))) }
        let installed = catalog.installed.filter { $0.bundleID != me }
        if !installed.isEmpty || catalog.isScanning { groups.append(AppGroup(kind: .installed, apps: installed)) }
        return groups
    }

    private func hasRing(_ app: AppInfo) -> Bool {
        model.config.profileIndex(bundleID: app.bundleID) != nil
    }

    // MARK: Actions

    /// Adds a ring for `app` (or finds its existing one), shows it and closes the sheet.
    private func choose(_ app: AppInfo) {
        let id = model.addAppProfile(bundleID: app.bundleID, name: app.name, copyGlobal: startsWithCopy)
        onChoose(id)
        dismiss()
    }

    private func chooseCurrent(_ current: String?, in groups: [AppGroup]) {
        for group in groups {
            if let app = group.apps.first(where: { group.rowID($0) == current }) {
                choose(app)
                return
            }
        }
    }

    private func move(_ move: GridNavigation.Move, from current: String?, _ navigation: GridNavigation) -> KeyPress.Result {
        guard let target = navigation.target(from: current, move) else { return .ignored }
        highlighted = target
        return .handled
    }

    private func chooseFromDisk() {
        let panel = NSOpenPanel()
        panel.title = "Choose an App"
        panel.message = "Choose the app that should get its own ring."
        panel.prompt = "Create Ring"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        FilePanel.present(panel) { url in
            guard let info = AppCatalog.appInfo(at: url) else {
                alert = PaneAlert(title: "Can't Use This App",
                                  message: "“\(url.deletingPathExtension().lastPathComponent)” has no bundle identifier, so Halo can't tell when it's in front.")
                return
            }
            choose(info)
        }
    }
}

/// Where keyboard focus is inside the sheet.
private enum SheetField: Hashable {
    case search, grid
}

private struct AppGroup: Identifiable {
    enum Kind: String {
        case suggested, installed, results
    }

    var kind: Kind
    var apps: [AppInfo]

    var id: Kind { kind }

    /// A suggested app is listed under All Apps too, so tiles are identified per group.
    func rowID(_ app: AppInfo) -> String { kind.rawValue + ":" + app.bundleID }

    var title: String {
        switch kind {
        case .suggested: "Suggested"
        case .installed: "All Apps"
        case .results: "Results"
        }
    }
}

/// A ring of dots around an app glyph: "a ring for an app".
private struct AppRingGlyph: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.12))
            ForEach(0..<8, id: \.self) { i in
                Circle()
                    .fill(Color.accentColor.opacity(0.35))
                    .frame(width: 10, height: 10)
                    .offset(y: -19)
                    .rotationEffect(.degrees(Double(i) * 45))
            }
            Image(systemName: "app.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.tint)
        }
        .accessibilityHidden(true)
    }
}
