import AppKit
import HaloCore
import SwiftUI

/// How the ring looks and feels, with a large live preview of the Everywhere ring that
/// follows every change (including slider drags) as it happens.
struct AppearancePane: View {
    @ViewState private var scaleDraft: Double?
    @ViewState private var speedDraft: Double?

    private var model: AppModel { .shared }

    /// Saved settings with any in-progress slider drag applied, so previews follow the thumb.
    private var previewSettings: AppSettings {
        var settings = model.settings
        if let scaleDraft { settings.ringScale = scaleDraft }
        if let speedDraft { settings.animationSpeed = speedDraft }
        return settings
    }

    var body: some View {
        let settings = previewSettings
        let ring = model.config.globalRing
        VStack(spacing: 0) {
            PreviewStage(ring: ring, settings: settings)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 4)
            Form {
                ThemeSection(ring: ring, settings: settings)
                RingSection(scaleDraft: $scaleDraft)
                MotionSection(speedDraft: $speedDraft)
            }
            .formStyle(.grouped)
        }
    }
}

/// The slot the previews highlight at rest: the first one with an action.
private func restingSlot(in ring: Ring) -> Int {
    ring.slots.firstIndex { $0.action != nil } ?? 0
}

/// The large preview at the top of the pane, at true relative size.
private struct PreviewStage: View {
    let ring: Ring
    let settings: AppSettings

    var body: some View {
        RingPreview(ring: ring, settings: settings, restingHighlight: restingSlot(in: ring),
                    side: 270, showsSizeChanges: true, followsPointer: true)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background { PreviewBackdrop(cornerRadius: 16) }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                Text("Point at the preview to try it")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                    .padding(10)
                    .accessibilityHidden(true)
            }
    }
}

// MARK: - Theme

private struct ThemeSection: View {
    let ring: Ring
    let settings: AppSettings

    var body: some View {
        Section {
            HStack(spacing: 14) {
                ForEach(RingTheme.allCases, id: \.self) { theme in
                    ThemeCard(theme: theme, ring: ring, settings: settings, isSelected: settings.theme == theme) {
                        AppModel.shared.updateSettings("Change Theme") { $0.theme = theme }
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Theme")
        }
    }
}

/// A clickable card with a mini live preview of one theme.
private struct ThemeCard: View {
    let theme: RingTheme
    let ring: Ring
    let settings: AppSettings
    let isSelected: Bool
    let choose: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Button(action: choose) {
            VStack(alignment: .leading, spacing: 10) {
                RingPreview(ring: ring, settings: cardSettings, restingHighlight: restingSlot(in: ring), side: 130)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background { PreviewBackdrop(cornerRadius: 10) }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                HStack(spacing: 8) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.headline)
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(10)
            .background(.fill.quaternary, in: shape)
            .overlay {
                shape.strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(borderStyle),
                                   lineWidth: isSelected ? 2.5 : 1)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) theme")
        .accessibilityHint(subtitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var borderStyle: some ShapeStyle {
        contrast == .increased ? AnyShapeStyle(.primary) : AnyShapeStyle(.separator)
    }

    /// The user's look in this card's theme; labels only in the hub, so the small card stays clean.
    private var cardSettings: AppSettings {
        var s = settings
        s.theme = theme
        s.ringScale = 1
        s.labelMode = .hub
        s.showSlotNumbers = false
        return s
    }

    private var title: String {
        switch theme {
        case .classic: "Classic"
        case .glass: "Glass"
        }
    }

    private var subtitle: String {
        switch theme {
        case .classic: "Logitech-style bubbles"
        case .glass: "Liquid Glass ring"
        }
    }
}

// MARK: - Ring

private struct RingSection: View {
    @Binding var scaleDraft: Double?

    private var model: AppModel { .shared }

    var body: some View {
        let settings = model.settings
        let scale = DeferredSliderValue(saved: settings.ringScale, draft: $scaleDraft) { value in
            AppModel.shared.updateSettings("Change Ring Size") { $0.ringScale = value }
        }
        let percent = Int((scale.value.wrappedValue * 100).rounded())

        Section {
            LabeledContent {
                Slider(value: scale.value, in: AppSettings.ringScaleRange) {
                    Text("Size")
                } minimumValueLabel: {
                    Image(systemName: "circle").imageScale(.small)
                } maximumValueLabel: {
                    Image(systemName: "circle").imageScale(.large)
                } ticks: {
                    SliderTick("S", 0.8)
                    SliderTick("M", 1.0)
                    SliderTick("L", 1.2)
                } onEditingChanged: { scale.editingChanged($0) }
                .labelsHidden()
                .accessibilityValue("\(percent) percent")
            } label: {
                Text("Size")
                Text("\(percent)%").monospacedDigit()
            }

            Picker(selection: .appSetting(\.labelMode, "Change Labels")) {
                Text("In Hub").tag(LabelMode.hub)
                Text("Always").tag(LabelMode.always)
                Text("Off").tag(LabelMode.none)
            } label: {
                Text("Labels")
                Text(labelExplanation(settings.labelMode))
            }
            .pickerStyle(.segmented)

            Toggle(isOn: .appSetting(\.closesGaps, "Change Gap Closing")) {
                Text("Close up empty slots")
                Text("The ring shows only your actions, evenly spaced, so 3 or 5 actions look as tidy as 8. The editor still shows every slot.")
            }

            Toggle(isOn: .appSetting(\.showSlotNumbers, "Change Slot Numbers")) {
                Text("Show slot numbers")
                Text("Numbers 1 to 9 and 0 on the slots. Press one to choose its action.")
            }

            LabeledContent {
                AccentSwatches(selected: settings.accent)
            } label: {
                Text("Accent color")
                Text("Highlights the slot you point at.")
            }
        } header: {
            Text("Ring")
        }
    }

    private func labelExplanation(_ mode: LabelMode) -> String {
        switch mode {
        case .hub: "The highlighted action's name appears in the center."
        case .always: "Every slot shows its name, and the center names the highlight."
        case .none: "Icons only."
        }
    }
}

/// A row of colour swatches for the ring's accent.
private struct AccentSwatches: View {
    let selected: RingColor

    var body: some View {
        HStack(spacing: 2) {
            ForEach(RingColor.Preset.allCases, id: \.self) { preset in
                swatch(.preset(preset))
            }
            if case .custom = selected {
                swatch(selected)
            }
        }
    }

    private func swatch(_ color: RingColor) -> some View {
        AccentSwatch(color: color, isSelected: color == selected) {
            AppModel.shared.updateSettings("Change Accent Color") { $0.accent = color }
        }
    }
}

private struct AccentSwatch: View {
    let color: RingColor
    let isSelected: Bool
    let choose: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: choose) {
            Circle()
                .fill(color.color)
                .frame(width: 16, height: 16)
                .overlay {
                    Circle().strokeBorder(.primary.opacity(contrast == .increased ? 0.7 : 0.15), lineWidth: 1)
                }
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 1)
                    }
                }
                .padding(3)
                .overlay {
                    Circle().strokeBorder(isSelected ? color.color : .clear, lineWidth: 2)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(color.name)
        .accessibilityLabel(color.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Motion and feedback

private struct MotionSection: View {
    @Binding var speedDraft: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var model: AppModel { .shared }

    var body: some View {
        let settings = model.settings
        let speed = DeferredSliderValue(saved: settings.animationSpeed, draft: $speedDraft) { value in
            AppModel.shared.updateSettings("Change Animation Speed") { $0.animationSpeed = value }
        }
        let speedName = Self.name(forSpeed: speed.value.wrappedValue)

        Section {
            LabeledContent {
                Slider(value: speed.value, in: AppSettings.animationSpeedRange, step: 0.25) {
                    Text("Animation speed")
                } minimumValueLabel: {
                    Text("Off")
                } maximumValueLabel: {
                    Text("Fast")
                } onEditingChanged: { speed.editingChanged($0) }
                .labelsHidden()
                .accessibilityValue(speedName)
            } label: {
                Text("Animation: \(speedName)")
                if reduceMotion {
                    Text("Reduce Motion is on, so the ring fades instead of moving.")
                } else {
                    Text("How quickly the ring opens, highlights and closes.")
                }
            }

            Toggle(isOn: .appSetting(\.hapticsEnabled, "Change Haptics")) {
                Text("Haptic feedback")
                Text("Plays only on a Force Touch trackpad while your finger rests on it. Mice can't play haptics.")
            }

            Toggle(isOn: Binding {
                AppModel.shared.settings.soundsEnabled
            } set: { isOn in
                AppModel.shared.updateSettings("Change Sounds") { $0.soundsEnabled = isOn }
                if isOn { Feedback.play(.select) }
            }) {
                Text("Sounds")
                Text("Soft sounds when the ring opens, when an action runs and when a slot is empty.")
            }
        } header: {
            Text("Motion and Feedback")
        }
    }

    static func name(forSpeed speed: Double) -> String {
        switch speed {
        case ..<0.01: "Off"
        case ..<0.74: "Slow"
        case ..<1.26: "Normal"
        default: "Fast"
        }
    }
}
