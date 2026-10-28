import AppKit
import HaloCore

/// Trackpad haptics and optional sounds, gated by the user's settings.
enum Feedback {
    enum Event {
        /// The highlight moved to another slot.
        case highlight
        /// A slot was chosen.
        case select
        /// The slot can't be chosen (empty) or the action failed.
        case reject
        /// The ring opened.
        case open
    }

    static func play(_ event: Event) {
        let settings = AppModel.shared.settings
        if settings.hapticsEnabled {
            let pattern: NSHapticFeedbackManager.FeedbackPattern = switch event {
            case .highlight: .alignment
            case .select: .levelChange
            case .reject: .generic
            case .open: .alignment
            }
            NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
        }
        if settings.soundsEnabled {
            let name: NSSound.Name? = switch event {
            case .highlight: nil
            case .select: "Pop"
            case .reject: "Funk"
            case .open: "Tink"
            }
            if let name, let sound = NSSound(named: name) {
                sound.volume = 0.25
                sound.play()
            }
        }
    }
}
