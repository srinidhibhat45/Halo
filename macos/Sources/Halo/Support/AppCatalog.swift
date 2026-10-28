import AppKit
import HaloCore
import Observation

/// An installed application.
struct AppInfo: Identifiable, Hashable, Sendable {
    var bundleID: String
    var name: String
    var url: URL

    var id: String { bundleID }
}

/// Installed apps and their icons. Icons are cached; the installed list is scanned lazily.
@Observable
final class AppCatalog {
    static let shared = AppCatalog()

    /// Installed apps sorted by name (empty until `refresh()` finishes).
    private(set) var installed: [AppInfo] = []
    private(set) var isScanning = false

    @ObservationIgnored private var iconCache: [String: NSImage] = [:]
    @ObservationIgnored private var infoCache: [String: AppInfo] = [:]

    private init() {}

    /// Rescans the standard application folders in the background.
    func refresh() {
        guard !isScanning else { return }
        isScanning = true
        Task.detached(priority: .utility) {
            let apps = Self.scanApplications()
            await MainActor.run {
                self.installed = apps
                for app in apps { self.infoCache[app.bundleID] = app }
                self.isScanning = false
            }
        }
    }

    /// Apps currently running with a Dock presence (regular activation policy), Halo excluded.
    var runningApps: [AppInfo] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in
                guard let id = app.bundleIdentifier, let url = app.bundleURL else { return nil }
                return AppInfo(bundleID: id, name: app.localizedName ?? url.deletingPathExtension().lastPathComponent, url: url)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func info(bundleID: String) -> AppInfo? {
        if let cached = infoCache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let info = Self.appInfo(at: url)
        if let info { infoCache[bundleID] = info }
        return info
    }

    nonisolated static func appInfo(at url: URL) -> AppInfo? {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
        let name = (bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.infoDictionary?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return AppInfo(bundleID: id, name: name, url: url)
    }

    /// The app's icon, or a generic app icon if it isn't installed. Cached per bundle ID.
    func icon(forBundleID bundleID: String) -> NSImage {
        if let cached = iconCache[bundleID] { return cached }
        let image: NSImage
        if !bundleID.isEmpty, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = NSWorkspace.shared.icon(for: .applicationBundle)
        }
        iconCache[bundleID] = image
        return image
    }

    /// Icon for any file or folder path.
    func icon(forPath path: String) -> NSImage {
        let expanded = (path as NSString).expandingTildeInPath
        if let cached = iconCache["path:" + expanded] { return cached }
        let image = NSWorkspace.shared.icon(forFile: expanded)
        iconCache["path:" + expanded] = image
        return image
    }

    private nonisolated static func scanApplications() -> [AppInfo] {
        let fm = FileManager.default
        let roots = [
            "/Applications", "/Applications/Utilities",
            "/System/Applications", "/System/Applications/Utilities",
            (NSHomeDirectory() as NSString).appendingPathComponent("Applications"),
        ].map { URL(fileURLWithPath: $0, isDirectory: true) }

        var seen = Set<String>()
        var apps: [AppInfo] = []
        for root in roots {
            guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for url in items {
                if url.pathExtension == "app" {
                    if let info = appInfo(at: url), seen.insert(info.bundleID).inserted { apps.append(info) }
                } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                          let nested = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                    // One level down, e.g. /Applications/Adobe Photoshop 2026/Adobe Photoshop 2026.app
                    for inner in nested where inner.pathExtension == "app" {
                        if let info = appInfo(at: inner), seen.insert(info.bundleID).inserted { apps.append(info) }
                    }
                }
            }
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
