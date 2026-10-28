import AppKit
import SwiftUI

/// A searchable list of apps: running apps first, then recently used, then everything installed,
/// plus "Choose Another App…" for any .app on disk. Picks with a single click, or Return in the
/// search field for the first match.
struct AppPickerView: View {
    /// Shown with a checkmark.
    var selectedBundleID: String?
    var onPick: (AppInfo) -> Void

    @ViewState private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        let sections = appSections
        VStack(spacing: 0) {
            PickerSearchField(prompt: "Search Apps", text: $query, isFocused: $searchFocused)
                .onSubmit {
                    if let first = sections.first?.apps.first { onPick(first) }
                }
                .padding(10)

            Divider()

            if sections.isEmpty {
                if AppCatalog.shared.isScanning {
                    ProgressView("Finding Apps…")
                        .frame(maxHeight: .infinity)
                } else {
                    ContentUnavailableView.search(text: query)
                }
            } else {
                List {
                    ForEach(sections, id: \.title) { section in
                        Section(section.title) {
                            ForEach(section.apps) { app in
                                row(app)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            HStack {
                Button("Choose Another App…", systemImage: "folder") {
                    Task { @MainActor in
                        guard let url = await EditorOpenPanel.chooseApplication() else { return }
                        if let app = AppCatalog.appInfo(at: url) {
                            onPick(app)
                        } else {
                            Log.app.error("Not an app bundle: \(url.lastPathComponent, privacy: .public)")
                            NSSound.beep()
                        }
                    }
                }
                Spacer()
                if AppCatalog.shared.isScanning {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Finding apps")
                }
            }
            .padding(10)
        }
        .onAppear {
            if AppCatalog.shared.installed.isEmpty { AppCatalog.shared.refresh() }
            Task { @MainActor in searchFocused = true }
        }
    }

    private func row(_ app: AppInfo) -> some View {
        Button {
            onPick(app)
        } label: {
            HStack(spacing: 8) {
                Image(nsImage: AppCatalog.shared.icon(forBundleID: app.bundleID))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                Text(app.name)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if app.bundleID == selectedBundleID {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(app.url.path(percentEncoded: false))
        .accessibilityLabel(app.name)
        .accessibilityAddTraits(app.bundleID == selectedBundleID ? .isSelected : [])
    }

    private var appSections: [(title: String, apps: [AppInfo])] {
        let catalog = AppCatalog.shared
        let running = catalog.runningApps
        let recent = AppModel.shared.recentApps
        let installed = catalog.installed
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else {
            var seen = Set<String>()
            let matches = (running + recent + installed)
                .filter { seen.insert($0.bundleID).inserted }
                .filter { app in
                    trimmed.split(separator: " ").allSatisfy {
                        app.name.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                            || app.bundleID.range(of: $0, options: .caseInsensitive) != nil
                    }
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return matches.isEmpty ? [] : [("Results", matches)]
        }
        let runningIDs = Set(running.map(\.bundleID))
        let recentOnly = recent.filter { !runningIDs.contains($0.bundleID) }
        return [("Running", running), ("Recently Used", recentOnly), ("All Apps", installed)].filter { !$0.apps.isEmpty }
    }
}
