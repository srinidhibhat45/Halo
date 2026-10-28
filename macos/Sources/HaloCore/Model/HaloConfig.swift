import Foundation

/// Everything the user configures. Persisted as JSON by `ConfigFile`.
public struct HaloConfig: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var settings: AppSettings
    /// The ring used in every app without its own enabled ring.
    public var globalRing: Ring
    /// App-specific rings, in sidebar order.
    public var appProfiles: [AppProfile]

    public init(
        settings: AppSettings = AppSettings(),
        globalRing: Ring = DefaultRings.global(),
        appProfiles: [AppProfile] = []
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.settings = settings
        self.globalRing = globalRing
        self.appProfiles = appProfiles
    }

    public static var `default`: HaloConfig { HaloConfig() }

    /// The ring to show when `bundleID` is the frontmost app.
    public func resolvedRing(forFrontmostBundleID bundleID: String?) -> ResolvedRing {
        guard settings.appRingsEnabled,
              let bundleID,
              let profile = appProfiles.first(where: { $0.isEnabled && $0.bundleID == bundleID })
        else {
            return ResolvedRing(ring: globalRing, profile: nil)
        }
        var ring = profile.ring
        if profile.inheritsGlobalSlots {
            for i in ring.slots.indices where ring.slots[i].action == nil {
                guard globalRing.slots.indices.contains(i), globalRing.slots[i].action != nil else { continue }
                var inherited = globalRing.slots[i]
                inherited.id = ring.slots[i].id   // keep ids unique within the resolved ring
                ring[i] = inherited
            }
        }
        return ResolvedRing(ring: ring, profile: profile)
    }

    public func profileIndex(id: AppProfile.ID) -> Int? { appProfiles.firstIndex { $0.id == id } }
    public func profileIndex(bundleID: String) -> Int? { appProfiles.firstIndex { $0.bundleID == bundleID } }

    private enum CodingKeys: String, CodingKey { case schemaVersion, settings, globalRing, appProfiles }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = (try? c.decodeIfPresent(Int.self, forKey: .schemaVersion)) ?? Self.currentSchemaVersion
        self.settings = (try? c.decodeIfPresent(AppSettings.self, forKey: .settings)) ?? AppSettings()
        // The global ring is the one thing worth failing loudly for: a config without it is not ours.
        self.globalRing = try c.decode(Ring.self, forKey: .globalRing)
        self.appProfiles = (try? c.decodeIfPresent([AppProfile].self, forKey: .appProfiles)) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try c.encode(settings, forKey: .settings)
        try c.encode(globalRing, forKey: .globalRing)
        try c.encode(appProfiles, forKey: .appProfiles)
    }
}

/// A ring that replaces the global ring while a specific app is frontmost.
public struct AppProfile: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var bundleID: String
    public var appName: String
    public var isEnabled: Bool
    public var ring: Ring
    /// Empty slots show the global ring's action at the same position.
    public var inheritsGlobalSlots: Bool

    public init(id: UUID = UUID(), bundleID: String, appName: String, isEnabled: Bool = true, ring: Ring = Ring(), inheritsGlobalSlots: Bool = false) {
        self.id = id
        self.bundleID = bundleID
        self.appName = appName
        self.isEnabled = isEnabled
        self.ring = ring
        self.inheritsGlobalSlots = inheritsGlobalSlots
    }

    private enum CodingKeys: String, CodingKey { case id, bundleID, appName, isEnabled, ring, inheritsGlobalSlots }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        self.bundleID = try c.decode(String.self, forKey: .bundleID)
        self.appName = (try? c.decodeIfPresent(String.self, forKey: .appName)) ?? bundleID
        self.isEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? true
        self.ring = (try? c.decodeIfPresent(Ring.self, forKey: .ring)) ?? Ring()
        self.inheritsGlobalSlots = (try? c.decodeIfPresent(Bool.self, forKey: .inheritsGlobalSlots)) ?? false
    }
}

/// The ring chosen for the current frontmost app.
public struct ResolvedRing: Hashable, Sendable {
    public var ring: Ring
    /// The app profile in effect, or nil for the global ring.
    public var profile: AppProfile?

    public init(ring: Ring, profile: AppProfile?) {
        self.ring = ring
        self.profile = profile
    }
}
