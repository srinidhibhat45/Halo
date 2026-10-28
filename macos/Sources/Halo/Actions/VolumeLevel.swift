import AudioToolbox
import CoreAudio

/// The default output device's volume through CoreAudio. Reading needs no permission; writing is
/// the no-HUD fallback for volume slots when Accessibility (media keys) isn't granted.
nonisolated enum VolumeLevel {
    /// Step of one hardware volume key press (1/16).
    static let step = 1.0 / 16

    /// Current output volume, 0...1, or nil when the device has no software volume (e.g. HDMI).
    static func current() -> Double? {
        guard let device = defaultOutputDevice(),
              let value = read(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, as: Float32(0)) else { return nil }
        return Double(value)
    }

    /// Whether the default output is muted, or nil when it has no mute control.
    static func isMuted() -> Bool? {
        guard let device = defaultOutputDevice(), let value = read(device, kAudioDevicePropertyMute, as: UInt32(0)) else { return nil }
        return value != 0
    }

    /// Changes the volume by `delta` (unmuting, like the volume keys); returns the new level.
    static func adjust(by delta: Double) -> Double? {
        guard let device = defaultOutputDevice(), let level = current() else { return nil }
        let next = Float32(min(max(level + delta, 0), 1))
        guard write(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, next) else { return nil }
        if isMuted() == true { _ = write(device, kAudioDevicePropertyMute, UInt32(0)) }
        return Double(next)
    }

    /// Toggles mute; returns the new state.
    static func toggleMute() -> Bool? {
        guard let device = defaultOutputDevice(), let muted = isMuted() else { return nil }
        return write(device, kAudioDevicePropertyMute, UInt32(muted ? 0 : 1)) ? !muted : nil
    }

    private static func defaultOutputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private static func outputAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }

    private static func read<T: BitwiseCopyable>(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector, as initial: T) -> T? {
        var address = outputAddress(selector)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func write<T: BitwiseCopyable>(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: T) -> Bool {
        var address = outputAddress(selector)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return false }
        var value = value
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value) == noErr
    }
}
