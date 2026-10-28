import AppKit
import HaloCore
import Observation

/// What a new app ring starts with.
enum AppRingStart: Hashable, CaseIterable {
    /// The app's own actions (presets) when Halo knows some; other slots show Everywhere's.
    case appActions
    /// A copy of the Everywhere ring.
    case copyOfEverywhere
    /// Empty slots that show Everywhere's actions until filled.
    case empty
}

/// Which ring an edit applies to.
enum RingTarget: Hashable, Sendable {
    case global
    case app(AppProfile.ID)
}

/// The single source of truth for the user's configuration.
///
/// Every change goes through `update(_:_:)` (or a helper built on it) so that undo/redo, saving
/// and side effects (re-registering the trigger, menu bar icon, login item) stay consistent.
@Observable
final class AppModel {
    static let shared = AppModel()

    private(set) var config: HaloConfig
    private(set) var loadOutcome: ConfigFile.LoadOutcome
    /// While paused the trigger is ignored.
    var isPaused = false
    /// Most recently activated apps (newest first, Halo excluded), for "Add app ring" suggestions.
    private(set) var recentApps: [AppInfo] = []

    /// Called after settings change, with (old, new). Set by the app delegate.
    @ObservationIgnored var settingsDidChange: ((AppSettings, AppSettings) -> Void)?

    @ObservationIgnored let undoManager = UndoManager()
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?

    init(fileURL: URL = ConfigFile.defaultURL) {
        self.fileURL = fileURL
        let (config, outcome) = ConfigFile.load(from: fileURL)
        self.config = config
        self.loadOutcome = outcome
        switch outcome {
        case .loaded: Log.config.info("Loaded config from \(fileURL.path, privacy: .public)")
        case .createdDefault: Log.config.info("No config yet; using defaults")
        case .recoveredFromCorruption(let aside): Log.config.error("Config unreadable; moved to \(aside.path, privacy: .public)")
        case .unreadable(let message): Log.config.fault("Config unreadable and could not be moved: \(message, privacy: .public)")
        }
        undoManager.levelsOfUndo = 100
        observeActivations()
    }

    var settings: AppSettings { config.settings }

    // MARK: Core mutation

    /// Applies `body` to the config as one undoable step named `actionName`.
    func update(_ actionName: String, _ body: (inout HaloConfig) -> Void) {
        var next = config
        body(&next)
        guard next != config else { return }
        apply(next, actionName: actionName)
    }

    private func apply(_ next: HaloConfig, actionName: String) {
        let previous = config
        config = next
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                // Bookkeeping that the user didn't do in the configurator is never undone.
                var restored = previous
                restored.settings.hasCompletedOnboarding = model.config.settings.hasCompletedOnboarding
                model.apply(restored, actionName: actionName)
            }
        }
        undoManager.setActionName(actionName)
        if previous.settings != next.settings {
            settingsDidChange?(previous.settings, next.settings)
        }
        scheduleSave()
    }

    // MARK: Settings

    func updateSettings(_ actionName: String = "Change Setting", _ body: (inout AppSettings) -> Void) {
        update(actionName) { body(&$0.settings) }
    }

    // MARK: Rings

    /// The ring for `target` at a folder `path` (indices of folder slots), or nil if it no longer exists.
    func ring(_ target: RingTarget, path: [Int] = []) -> Ring? {
        switch target {
        case .global:
            return config.globalRing.ring(at: path)
        case .app(let id):
            guard let i = config.profileIndex(id: id) else { return nil }
            return config.appProfiles[i].ring.ring(at: path)
        }
    }

    /// Edits the ring for `target` at folder `path` as one undoable step.
    func updateRing(_ target: RingTarget, path: [Int] = [], _ actionName: String, _ body: (inout Ring) -> Void) {
        update(actionName) { config in
            switch target {
            case .global:
                config.globalRing.updateRing(at: path, body)
            case .app(let id):
                guard let i = config.profileIndex(id: id) else { return }
                config.appProfiles[i].ring.updateRing(at: path, body)
            }
        }
    }

    /// Replaces one slot.
    func setSlot(_ slot: Slot, at index: Int, in target: RingTarget, path: [Int] = [], actionName: String = "Edit Slot") {
        updateRing(target, path: path, actionName) { ring in
            guard ring.slots.indices.contains(index) else { return }
            ring[index] = slot
        }
    }

    // MARK: App profiles

    func profile(_ id: AppProfile.ID) -> AppProfile? {
        config.profileIndex(id: id).map { config.appProfiles[$0] }
    }

    /// Adds an app ring (or returns the existing one for that app). New rings start empty and
    /// inherit the global ring's slots until filled, unless `copyGlobal` copies them outright.
    @discardableResult
    func addAppProfile(bundleID: String, name: String, start: AppRingStart = .empty) -> AppProfile.ID {
        if let existing = config.profileIndex(bundleID: bundleID) { return config.appProfiles[existing].id }
        let slotCount = config.globalRing.slotCount
        let ring: Ring
        var inherits = true
        switch start {
        case .copyOfEverywhere:
            ring = Self.freshIDs(config.globalRing)
            inherits = false
        case .appActions:
            // The app's own actions first; any slots left show Everywhere's actions.
            var filled = Ring(slotCount: slotCount)
            for (i, slot) in AppActionPresets.suggestedSlots(forBundleID: bundleID, limit: slotCount).enumerated() {
                filled[i] = slot
            }
            ring = filled
        case .empty:
            ring = Ring(slotCount: slotCount)
        }
        let profile = AppProfile(bundleID: bundleID, appName: name, ring: ring, inheritsGlobalSlots: inherits)
        update("Add \(name) Ring") { $0.appProfiles.append(profile) }
        return profile.id
    }

    /// Fills the empty slots of an app ring's top level with the app's preset actions it doesn't
    /// have yet. Returns how many were added.
    @discardableResult
    func addSuggestedActions(to id: AppProfile.ID) -> Int {
        guard let profile = profile(id) else { return 0 }
        let present = Set(profile.ring.slots.compactMap(\.action))
        let fresh = AppActionPresets.suggestedSlots(forBundleID: profile.bundleID, limit: Ring.slotRange.upperBound)
            .filter { $0.action.map { !present.contains($0) } ?? false }
        let empty = profile.ring.slots.indices.filter { profile.ring.slots[$0].action == nil }
        let count = min(fresh.count, empty.count)
        guard count > 0 else { return 0 }
        updateRing(.app(id), "Add \(profile.appName) Actions") { ring in
            for (slot, index) in zip(fresh, empty) { ring[index] = slot }
        }
        return count
    }

    func updateProfile(_ id: AppProfile.ID, _ actionName: String, _ body: (inout AppProfile) -> Void) {
        update(actionName) { config in
            guard let i = config.profileIndex(id: id) else { return }
            body(&config.appProfiles[i])
        }
    }

    func removeAppProfile(_ id: AppProfile.ID) {
        let name = profile(id)?.appName ?? "App"
        update("Remove \(name) Ring") { $0.appProfiles.removeAll { $0.id == id } }
    }

    func moveAppProfiles(from source: IndexSet, to destination: Int) {
        update("Reorder App Rings") { $0.appProfiles.move(fromOffsets: source, toOffset: destination) }
    }

    // MARK: Whole config

    /// Replaces rings and preferences, keeping settings that belong to this Mac (launch at
    /// login, onboarding state), as Reset does.
    func replaceConfig(with imported: HaloConfig, actionName: String = "Import Configuration") {
        var next = imported
        next.settings.launchAtLogin = config.settings.launchAtLogin
        next.settings.hasCompletedOnboarding = config.settings.hasCompletedOnboarding
        apply(next, actionName: actionName)
    }

    func resetToDefaults() {
        var fresh = HaloConfig.default
        // Keep the user's trigger and onboarding state; "reset" means rings and looks.
        fresh.settings.trigger = config.settings.trigger
        fresh.settings.hasCompletedOnboarding = config.settings.hasCompletedOnboarding
        fresh.settings.launchAtLogin = config.settings.launchAtLogin
        apply(fresh, actionName: "Reset to Defaults")
    }

    func exportData() throws -> Data { try ConfigFile.exportData(config) }

    func importData(_ data: Data) throws {
        replaceConfig(with: try ConfigFile.importConfig(from: data))
    }

    // MARK: Saving

    /// Debounced save; call `flush()` on quit.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func flush() {
        saveTask?.cancel()
        saveTask = nil
        saveNow()
    }

    private func saveNow() {
        if case .unreadable = loadOutcome {
            // Never overwrite a config we could not read or move aside.
            Log.config.error("Skipping save: original config is unreadable")
            return
        }
        do {
            try ConfigFile.save(config, to: fileURL)
        } catch {
            Log.config.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Recent apps

    private func observeActivations() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let id = app?.bundleIdentifier
            let name = app?.localizedName
            let url = app?.bundleURL
            let regular = app?.activationPolicy == .regular
            MainActor.assumeIsolated {
                guard let self, regular, let id, let url, id != Bundle.main.bundleIdentifier else { return }
                let info = AppInfo(bundleID: id, name: name ?? url.deletingPathExtension().lastPathComponent, url: url)
                self.recentApps.removeAll { $0.bundleID == id }
                self.recentApps.insert(info, at: 0)
                if self.recentApps.count > 8 { self.recentApps.removeLast(self.recentApps.count - 8) }
            }
        }
    }

    /// A copy of `ring` with new slot ids (recursively), so copies never share identity.
    static func freshIDs(_ ring: Ring) -> Ring {
        Ring(slots: ring.slots.map { slot in
            var s = slot
            s.id = UUID()
            if case .folder(let inner) = s.action { s.action = .folder(freshIDs(inner)) }
            return s
        })
    }
}
