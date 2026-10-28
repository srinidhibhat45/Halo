import HaloCore
import SwiftUI

/// Step 2: the trigger shortcut, how to put it on a mouse button, and a test of how the mouse
/// software sends it.
struct OnboardingShortcutPage: View {
    var body: some View {
        VStack(spacing: 18) {
            OnboardingHeader(
                title: "Your Shortcut",
                subtitle: "Halo opens with a keyboard shortcut. Keep the default or record your own, then point a mouse button at it."
            )
            recorderCard
            HStack(alignment: .top, spacing: 16) {
                OnboardingMouseGuide(trigger: trigger)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .onboardingCard()
                TriggerProbeCard()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .onboardingCard()
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var trigger: KeyCombo? { AppModel.shared.settings.trigger }

    private var triggerBinding: Binding<KeyCombo?> {
        Binding(
            get: { AppModel.shared.settings.trigger },
            set: { combo in AppModel.shared.updateSettings("Change Shortcut") { $0.trigger = combo } }
        )
    }

    private var recorderCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "keyboard")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ring shortcut").font(.headline)
                Text(trigger == nil
                     ? "No shortcut: the ring opens only from the menu bar."
                     : "Click the shortcut and press new keys to change it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            ShortcutRecorder(combo: triggerBinding, purpose: .trigger)
                .accessibilityLabel("Ring shortcut")
            if trigger != KeyCombo.defaultTrigger {
                Button("Use Default") {
                    AppModel.shared.updateSettings("Use Default Shortcut") { $0.trigger = .defaultTrigger }
                }
                .help("Use \(KeyCombo.defaultTrigger.displayString)")
            }
        }
        .onboardingCard()
    }
}

/// How to send the trigger from a mouse button in common mouse software.
struct OnboardingMouseGuide: View {
    let trigger: KeyCombo?

    private enum Software: String, CaseIterable, Identifiable {
        case logiOptions, betterTouchTool, other

        var id: String { rawValue }

        var title: String {
            switch self {
            case .logiOptions: "Logi Options+"
            case .betterTouchTool: "BetterTouchTool"
            case .other: "Others"
            }
        }
    }

    @ViewState private var software: Software = .logiOptions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Use a mouse button", systemImage: "computermouse")
                .font(.headline)
            Picker("Mouse software", selection: $software) {
                ForEach(Software.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    OnboardingStep(number: index + 1, text: step)
                }
            }
        }
    }

    private var steps: [String] {
        let keys = (trigger ?? .defaultTrigger).displayString
        switch software {
        case .logiOptions:
            return [
                "Open Logi Options+ and select your mouse.",
                "Click the button you want to use, such as a thumb or gesture button.",
                "Choose Keyboard shortcut as its action.",
                "Press \(keys) to record it.",
            ]
        case .betterTouchTool:
            return [
                "Open BetterTouchTool and select your mouse at the top.",
                "Add a trigger for the button you want, such as Other Mouse Button 4.",
                "Give it a keyboard shortcut action and press \(keys).",
                "Run the test to see whether it holds the keys down.",
            ]
        case .other:
            return [
                "In SteerMouse, USB Overdrive, Razer Synapse or similar, pick the button.",
                "Choose a keystroke or keyboard shortcut action and enter \(keys).",
                "Karabiner-Elements holds the keys as long as the button is down, ideal for hold and release.",
                "No mouse software? Press \(keys) on the keyboard.",
            ]
        }
    }
}
