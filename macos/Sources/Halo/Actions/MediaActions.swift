import AppKit
import HaloCore
import IOKit.hidsystem

/// Play/pause, tracks, volume, mute and brightness.
///
/// Media keys are posted as the same system-defined events the keyboard sends, so the system
/// routes them to the Now Playing app and shows its volume HUD. They don't wait for the trigger's
/// modifiers: scrolling over a volume slot while holding the trigger must respond at once.
enum MediaActions {
    static func run(_ command: MediaCommand, context: ActionContext) async -> ActionOutcome {
        switch command {
        case .playPause: return mediaKey(NX_KEYTYPE_PLAY)
        case .nextTrack: return mediaKey(NX_KEYTYPE_NEXT)
        case .previousTrack: return mediaKey(NX_KEYTYPE_PREVIOUS)
        case .volumeUp: return volume(NX_KEYTYPE_SOUND_UP) { VolumeLevel.adjust(by: VolumeLevel.step).map(percent) }
        case .volumeDown: return volume(NX_KEYTYPE_SOUND_DOWN) { VolumeLevel.adjust(by: -VolumeLevel.step).map(percent) }
        case .mute: return volume(NX_KEYTYPE_MUTE) { VolumeLevel.toggleMute().map { $0 ? "Muted" : "Sound on" } }
        case .brightnessUp: return brightness(up: true, near: context.ringCenter)
        case .brightnessDown: return brightness(up: false, near: context.ringCenter)
        }
    }

    private static func mediaKey(_ key: Int32) -> ActionOutcome {
        if let missing = PermissionCenter.shared.gate(.accessibility) { return missing }
        postAuxKey(key)
        return .success
    }

    /// Media key with the system HUD; without Accessibility, CoreAudio directly (no HUD, so the
    /// new level is reported instead).
    private static func volume(_ key: Int32, fallback: () -> String?) -> ActionOutcome {
        if PermissionCenter.shared.isGranted(.accessibility) {
            postAuxKey(key)
            return .success
        }
        if let message = fallback() { return .successWithMessage(message) }
        return .needsPermission(.accessibility)
    }

    /// Synthesized brightness keys are unreliable on Apple silicon, so Apple displays are set
    /// directly first (best effort, private DisplayServices); other displays get the key.
    private static func brightness(up: Bool, near point: CGPoint?) -> ActionOutcome {
        let delta: Float = up ? 1 / 16 : -1 / 16
        for display in DisplayBrightness.candidates(near: point) {
            if let level = DisplayBrightness.step(by: delta, display: display) {
                return .successWithMessage("Brightness \(percent(Double(level)))")
            }
        }
        return mediaKey(up ? NX_KEYTYPE_BRIGHTNESS_UP : NX_KEYTYPE_BRIGHTNESS_DOWN)
    }

    /// Posts an NX_SYSDEFINED / NX_SUBTYPE_AUX_CONTROL_BUTTONS key down and up.
    private static func postAuxKey(_ key: Int32) {
        for down in [true, false] {
            let state = down ? 0xA : 0xB   // NX_KEYDOWN / NX_KEYUP
            guard let event = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                                 modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                                                 timestamp: 0, windowNumber: 0, context: nil,
                                                 subtype: 8, data1: (Int(key) << 16) | (state << 8), data2: -1)?.cgEvent else {
                Log.actions.error("Could not create media key event \(key)")
                return
            }
            event.setIntegerValueField(.eventSourceUserData, value: KeySender.eventTag)
            event.post(tap: .cghidEventTap)
        }
    }

    private static func percent(_ level: Double) -> String {
        "\(Int((level * 100).rounded()))%"
    }
}

/// Brightness of Apple displays (built-in, Studio Display, Pro Display XDR) through the private
/// DisplayServices framework, looked up at run time so a missing symbol only disables this path.
enum DisplayBrightness {
    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let functions: (get: GetBrightness, set: SetBrightness)? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let get = dlsym(handle, "DisplayServicesGetBrightness"),
              let set = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        return (unsafeBitCast(get, to: GetBrightness.self), unsafeBitCast(set, to: SetBrightness.self))
    }()

    /// The display under `point` (AppKit coordinates) first, then the built-in display.
    static func candidates(near point: CGPoint?) -> [CGDirectDisplayID] {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        let ids = NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, NSRect)? in
            guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
            return (CGDirectDisplayID(number.uint32Value), screen.frame)
        }
        var ordered: [CGDirectDisplayID] = []
        if let point, let hit = ids.first(where: { $0.1.contains(point) }) { ordered.append(hit.0) }
        for (id, _) in ids where CGDisplayIsBuiltin(id) != 0 && !ordered.contains(id) { ordered.append(id) }
        return ordered
    }

    /// Changes `display`'s brightness by `delta`; the new level, or nil if the display isn't supported.
    static func step(by delta: Float, display: CGDirectDisplayID) -> Float? {
        guard let functions else { return nil }
        var level: Float = 0
        guard functions.get(display, &level) == 0 else { return nil }
        let next = min(max(level + delta, 0), 1)
        return functions.set(display, next) == 0 ? next : nil
    }
}
