import Foundation

/// How the trigger shortcut picks an action.
public enum SelectionMode: String, Codable, CaseIterable, Sendable {
    /// Quick tap keeps the ring open (click, press a number, or press the shortcut again on a
    /// highlighted slot); holding past the threshold selects on release.
    case auto
    /// The ring stays open after the shortcut; releasing never selects.
    case tapThenClick
    /// Release selects the highlighted slot; releasing with nothing highlighted cancels.
    case holdAndRelease
}

public enum RingTheme: String, Codable, CaseIterable, Sendable {
    /// Dark, solid ring modelled on Logitech's Actions Ring.
    case classic
    /// macOS Liquid Glass.
    case glass
}

public enum LabelMode: String, Codable, CaseIterable, Sendable {
    /// The highlighted slot's name appears in the hub.
    case hub
    /// Every slot shows a small caption under its icon, plus the hub label.
    case always
    /// Icons only.
    case none
}

public enum RingPlacement: String, Codable, CaseIterable, Sendable {
    /// Centred on the mouse pointer (clamped to the screen).
    case cursor
    /// Centred on the screen that contains the pointer.
    case screenCenter
}

/// App-wide preferences. Decoding is tolerant: missing keys fall back to defaults, so older
/// configs keep working when settings are added.
public struct AppSettings: Codable, Hashable, Sendable {
    /// The global shortcut that opens the ring; nil when the user cleared it.
    public var trigger: KeyCombo?
    public var selectionMode: SelectionMode
    /// Seconds the shortcut must be held before release counts as "hold" in `.auto`.
    public var holdThreshold: Double
    public var theme: RingTheme
    /// 0.8 ... 1.4 multiplier on the theme's ring size.
    public var ringScale: Double
    public var labelMode: LabelMode
    public var placement: RingPlacement
    /// 0.5 (slow) ... 2.0 (fast); 0 disables animation. Reduce Motion always wins.
    public var animationSpeed: Double
    public var accent: RingColor
    public var hapticsEnabled: Bool
    public var soundsEnabled: Bool
    public var showMenuBarIcon: Bool
    public var launchAtLogin: Bool
    /// Use app-specific rings when their app is frontmost.
    public var appRingsEnabled: Bool
    /// Show the numbers 1–9 on slots while the ring is open.
    public var showSlotNumbers: Bool
    /// Show a brief HUD after actions with no visible effect (copy, media, toggles).
    public var showConfirmations: Bool
    /// The live ring shows only filled slots, evenly spaced (no gaps for empty slots).
    public var closesGaps: Bool
    /// Check GitHub Releases for a newer Halo on launch and daily.
    public var checksForUpdates: Bool
    public var hasCompletedOnboarding: Bool

    public init(
        trigger: KeyCombo? = .defaultTrigger,
        selectionMode: SelectionMode = .auto,
        holdThreshold: Double = 0.28,
        theme: RingTheme = .classic,
        ringScale: Double = 1.0,
        labelMode: LabelMode = .hub,
        placement: RingPlacement = .cursor,
        animationSpeed: Double = 1.0,
        accent: RingColor = .preset(.blue),
        hapticsEnabled: Bool = true,
        soundsEnabled: Bool = false,
        showMenuBarIcon: Bool = true,
        launchAtLogin: Bool = false,
        appRingsEnabled: Bool = true,
        showSlotNumbers: Bool = false,
        showConfirmations: Bool = true,
        closesGaps: Bool = true,
        checksForUpdates: Bool = true,
        hasCompletedOnboarding: Bool = false
    ) {
        self.trigger = trigger
        self.selectionMode = selectionMode
        self.holdThreshold = holdThreshold
        self.theme = theme
        self.ringScale = ringScale
        self.labelMode = labelMode
        self.placement = placement
        self.animationSpeed = animationSpeed
        self.accent = accent
        self.hapticsEnabled = hapticsEnabled
        self.soundsEnabled = soundsEnabled
        self.showMenuBarIcon = showMenuBarIcon
        self.launchAtLogin = launchAtLogin
        self.appRingsEnabled = appRingsEnabled
        self.showSlotNumbers = showSlotNumbers
        self.showConfirmations = showConfirmations
        self.closesGaps = closesGaps
        self.checksForUpdates = checksForUpdates
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    public static let holdThresholdRange = 0.15...0.8
    public static let ringScaleRange = 0.8...1.4
    public static let animationSpeedRange = 0.0...2.0

    private enum CodingKeys: String, CodingKey {
        case trigger, selectionMode, holdThreshold, theme, ringScale, labelMode, placement
        case animationSpeed, accent, hapticsEnabled, soundsEnabled, showMenuBarIcon, launchAtLogin
        case appRingsEnabled, showSlotNumbers, showConfirmations, closesGaps, checksForUpdates, hasCompletedOnboarding
    }

    public init(from decoder: Decoder) throws {
        let d = AppSettings()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        // `trigger` distinguishes "absent" (use default) from explicit null (user cleared it).
        if c.contains(.trigger) {
            self.trigger = try? c.decodeIfPresent(KeyCombo.self, forKey: .trigger)
        } else {
            self.trigger = d.trigger
        }
        self.selectionMode = v(.selectionMode, d.selectionMode)
        self.holdThreshold = min(max(v(.holdThreshold, d.holdThreshold), Self.holdThresholdRange.lowerBound), Self.holdThresholdRange.upperBound)
        self.theme = v(.theme, d.theme)
        self.ringScale = min(max(v(.ringScale, d.ringScale), Self.ringScaleRange.lowerBound), Self.ringScaleRange.upperBound)
        self.labelMode = v(.labelMode, d.labelMode)
        self.placement = v(.placement, d.placement)
        self.animationSpeed = min(max(v(.animationSpeed, d.animationSpeed), Self.animationSpeedRange.lowerBound), Self.animationSpeedRange.upperBound)
        self.accent = v(.accent, d.accent)
        self.hapticsEnabled = v(.hapticsEnabled, d.hapticsEnabled)
        self.soundsEnabled = v(.soundsEnabled, d.soundsEnabled)
        self.showMenuBarIcon = v(.showMenuBarIcon, d.showMenuBarIcon)
        self.launchAtLogin = v(.launchAtLogin, d.launchAtLogin)
        self.appRingsEnabled = v(.appRingsEnabled, d.appRingsEnabled)
        self.showSlotNumbers = v(.showSlotNumbers, d.showSlotNumbers)
        self.showConfirmations = v(.showConfirmations, d.showConfirmations)
        self.closesGaps = v(.closesGaps, d.closesGaps)
        self.checksForUpdates = v(.checksForUpdates, d.checksForUpdates)
        self.hasCompletedOnboarding = v(.hasCompletedOnboarding, d.hasCompletedOnboarding)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(trigger, forKey: .trigger)   // encodes null when cleared
        try c.encode(selectionMode, forKey: .selectionMode)
        try c.encode(holdThreshold, forKey: .holdThreshold)
        try c.encode(theme, forKey: .theme)
        try c.encode(ringScale, forKey: .ringScale)
        try c.encode(labelMode, forKey: .labelMode)
        try c.encode(placement, forKey: .placement)
        try c.encode(animationSpeed, forKey: .animationSpeed)
        try c.encode(accent, forKey: .accent)
        try c.encode(hapticsEnabled, forKey: .hapticsEnabled)
        try c.encode(soundsEnabled, forKey: .soundsEnabled)
        try c.encode(showMenuBarIcon, forKey: .showMenuBarIcon)
        try c.encode(launchAtLogin, forKey: .launchAtLogin)
        try c.encode(appRingsEnabled, forKey: .appRingsEnabled)
        try c.encode(showSlotNumbers, forKey: .showSlotNumbers)
        try c.encode(showConfirmations, forKey: .showConfirmations)
        try c.encode(closesGaps, forKey: .closesGaps)
        try c.encode(checksForUpdates, forKey: .checksForUpdates)
        try c.encode(hasCompletedOnboarding, forKey: .hasCompletedOnboarding)
    }
}
